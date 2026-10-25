// k4fetch - small static HTTP/HTTPS client for the Kindle 4 NT.
//
// The device's own curl/OpenSSL (0.9.8j, 2009) can't talk to most modern TLS servers.
// k4fetch carries its own TLS (BearSSL 0.6) and a small, explicit set of root CAs compiled
// in from src/k4fetch/roots/*.pem. Needs a correct clock to validate certificates.
//
// Usage: k4fetch [-o FILE] [-t TIMEOUT_S] [-H 'Header: v']... [-X METHOD] [-d DATA]
//               [-i] [-k] [-v] URL
//   -o FILE   write the body to FILE (default stdout)
//   -t SECS   connect / per-read timeout (default 20)
//   -H HDR    extra request header (repeatable)
//   -X METH   request method (default GET, or POST with -d)
//   -d DATA   request body ("@file" reads it from a file)
//   -i        include the response status line and headers in the output
//   -k        don't verify the server certificate (debug only)
//   -v        verbose: timings, TLS version/cipher, redirects on stderr
// HTTP/1.1, SNI, up to 5 redirects, chunked and Content-Length bodies, no compression.
//
// Exit codes: 0 = 2xx, 1 = usage, 2 = DNS, 3 = connect/timeout/socket, 4 = TLS/certificate,
//             5 = HTTP status not 2xx (body still written), 6 = bad response,
//             7 = local file error, 8 = too many redirects

#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "bearssl.h"

#ifndef K4_VERSION
#define K4_VERSION "dev"  // set by tools/build.sh from git describe
#endif

extern const br_x509_trust_anchor KFETCH_TAs[];
extern const size_t KFETCH_TAs_NUM;

enum { E_OK = 0, E_USAGE = 1, E_DNS = 2, E_NET = 3, E_TLS = 4, E_HTTP = 5, E_PROTO = 6, E_FILE = 7, E_REDIR = 8 };

static int opt_verbose, opt_insecure, opt_include, opt_timeout = 20;
static double t_start;

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static void vlog(const char *fmt, ...) {
    if (!opt_verbose) return;
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "k4fetch: [%6.0f ms] ", now_ms() - t_start);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

static void fail(int code, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "k4fetch: ");
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
    exit(code);
}

/* ---------- URL ---------- */

struct url {
    int tls;
    char host[256];
    char port[8];
    char path[2048];
};

static int parse_url(const char *s, struct url *u) {
    const char *p;
    if (!strncasecmp(s, "https://", 8)) { u->tls = 1; p = s + 8; strcpy(u->port, "443"); }
    else if (!strncasecmp(s, "http://", 7)) { u->tls = 0; p = s + 7; strcpy(u->port, "80"); }
    else return -1;
    size_t hl = strcspn(p, "/?#");
    char hostport[300];
    if (hl == 0 || hl >= sizeof hostport) return -1;
    memcpy(hostport, p, hl);
    hostport[hl] = 0;
    char *colon = strrchr(hostport, ':');
    if (colon && hostport[0] != '[') {
        *colon = 0;
        if (strlen(colon + 1) >= sizeof u->port) return -1;
        strcpy(u->port, colon + 1);
    }
    if (strlen(hostport) >= sizeof u->host) return -1;
    strcpy(u->host, hostport);
    p += hl;
    size_t pl = strcspn(p, "#");
    if (pl + 2 > sizeof u->path) return -1;
    if (*p == '?') { u->path[0] = '/'; memcpy(u->path + 1, p, pl); u->path[pl + 1] = 0; }
    else if (pl == 0) strcpy(u->path, "/");
    else { memcpy(u->path, p, pl); u->path[pl] = 0; }
    return 0;
}

/* Resolve a Location header against the current URL into out. */
static int resolve_location(const struct url *base, const char *loc, char *out, size_t n) {
    if (!strncasecmp(loc, "http://", 7) || !strncasecmp(loc, "https://", 8))
        return snprintf(out, n, "%s", loc) < (int)n ? 0 : -1;
    const char *scheme = base->tls ? "https" : "http";
    int defport = !strcmp(base->port, base->tls ? "443" : "80");
    char origin[300];
    snprintf(origin, sizeof origin, "%s://%s%s%s", scheme, base->host, defport ? "" : ":", defport ? "" : base->port);
    if (loc[0] == '/' && loc[1] == '/')
        return snprintf(out, n, "%s:%s", scheme, loc) < (int)n ? 0 : -1;
    if (loc[0] == '/')
        return snprintf(out, n, "%s%s", origin, loc) < (int)n ? 0 : -1;
    // relative path: replace the last segment of the base path
    char dir[2048];
    snprintf(dir, sizeof dir, "%s", base->path);
    char *q = strchr(dir, '?');
    if (q) *q = 0;
    char *slash = strrchr(dir, '/');
    if (slash) slash[1] = 0;
    return snprintf(out, n, "%s%s%s", origin, dir, loc) < (int)n ? 0 : -1;
}

/* ---------- socket ---------- */

static int tcp_connect(const struct url *u) {
    struct addrinfo hints, *res, *ai;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;  // the K4 kernel has no IPv6; AAAA-only answers would just fail
    hints.ai_socktype = SOCK_STREAM;
    int r = getaddrinfo(u->host, u->port, &hints, &res);
    if (r) fail(E_DNS, "can't resolve %s: %s", u->host, gai_strerror(r));
    vlog("resolved %s", u->host);
    int fd = -1, err = 0;
    for (ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) { err = errno; continue; }
        int fl = fcntl(fd, F_GETFL);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        r = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (r < 0 && errno == EINPROGRESS) {
            struct pollfd p = { fd, POLLOUT, 0 };
            r = poll(&p, 1, opt_timeout * 1000);
            if (r == 1) {
                socklen_t sl = sizeof err;
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &sl);
                r = err ? -1 : 0;
            } else {
                err = r == 0 ? ETIMEDOUT : errno;
                r = -1;
            }
        } else if (r < 0) {
            err = errno;
        }
        if (r == 0) {
            fcntl(fd, F_SETFL, fl);
            struct timeval tv = { opt_timeout, 0 };
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
            int one = 1;
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) fail(E_NET, "can't connect to %s:%s: %s", u->host, u->port, strerror(err));
    vlog("connected to %s:%s", u->host, u->port);
    return fd;
}

/* ---------- -k: accept any certificate chain ---------- */

typedef struct {
    const br_x509_class *vtable;
    br_x509_minimal_context *inner;
} x509_insecure;

static void xi_start_chain(const br_x509_class **ctx, const char *name) {
    x509_insecure *x = (x509_insecure *)ctx;
    x->inner->vtable->start_chain(&x->inner->vtable, name);
}
static void xi_start_cert(const br_x509_class **ctx, uint32_t len) {
    x509_insecure *x = (x509_insecure *)ctx;
    x->inner->vtable->start_cert(&x->inner->vtable, len);
}
static void xi_append(const br_x509_class **ctx, const unsigned char *buf, size_t len) {
    x509_insecure *x = (x509_insecure *)ctx;
    x->inner->vtable->append(&x->inner->vtable, buf, len);
}
static void xi_end_cert(const br_x509_class **ctx) {
    x509_insecure *x = (x509_insecure *)ctx;
    x->inner->vtable->end_cert(&x->inner->vtable);
}
static unsigned xi_end_chain(const br_x509_class **ctx) {
    x509_insecure *x = (x509_insecure *)ctx;
    unsigned r = x->inner->vtable->end_chain(&x->inner->vtable);
    if (r) vlog("certificate check failed (BearSSL error %u), ignored because of -k", r);
    return 0;
}
static const br_x509_pkey *xi_get_pkey(const br_x509_class *const *ctx, unsigned *usages) {
    const x509_insecure *x = (const x509_insecure *)ctx;
    const br_x509_pkey *pk = x->inner->vtable->get_pkey(&x->inner->vtable, usages);
    if (pk) return pk;
    // The minimal engine withholds the key after most validation errors (expired, wrong
    // name, ...), but it has already decoded the server's key from the first certificate.
    if (!x->inner->pkey.key_type) return NULL;
    if (usages) *usages = BR_KEYTYPE_KEYX | BR_KEYTYPE_SIGN;
    return &x->inner->pkey;
}
static const br_x509_class x509_insecure_vtable = {
    sizeof(x509_insecure), xi_start_chain, xi_start_cert, xi_append, xi_end_cert, xi_end_chain, xi_get_pkey,
};

/* ---------- connection (plain or TLS) ---------- */

struct conn {
    int fd;
    int tls;
    br_ssl_client_context sc;
    br_x509_minimal_context xc;
    x509_insecure xi;
    unsigned char iobuf[BR_SSL_BUFSIZE_BIDI];
    br_sslio_context io;
    // response read buffer
    int ip_literal;
    unsigned char rbuf[8192];
    size_t rpos, rlen;
    int eof;
};

static int timed_out;  // set when a socket read hits SO_RCVTIMEO

static int sock_read(void *ctx, unsigned char *buf, size_t len) {
    for (;;) {
        ssize_t r = read(*(int *)ctx, buf, len);
        if (r > 0) return (int)r;
        if (r == 0) return -1;
        if (errno == EAGAIN || errno == EWOULDBLOCK) timed_out = 1;
        if (errno != EINTR) return -1;
    }
}

static int sock_write(void *ctx, const unsigned char *buf, size_t len) {
    for (;;) {
        ssize_t r = write(*(int *)ctx, buf, len);
        if (r > 0) return (int)r;
        if (r < 0 && errno == EINTR) continue;
        return -1;
    }
}

static const char *tls_version_name(unsigned v) {
    switch (v) {
    case BR_TLS10: return "TLS1.0";
    case BR_TLS11: return "TLS1.1";
    case BR_TLS12: return "TLS1.2";
    default: return "?";
    }
}

static void tls_fail(struct conn *c, const char *when) {
    int e = br_ssl_engine_last_error(&c->sc.eng);
    const char *hint = "";
    if (e == BR_ERR_X509_NOT_TRUSTED) hint = " (certificate not issued by a root k4fetch knows; see src/k4fetch/roots.txt)";
    else if (e == BR_ERR_X509_EXPIRED) hint = " (certificate expired or not yet valid; is the device clock right?)";
    else if (e == BR_ERR_X509_BAD_SERVER_NAME)
        hint = c->ip_literal ? " (BearSSL can't match certificates issued to IP addresses; use the host name)"
                             : " (certificate doesn't match the host name)";
    else if (e == BR_ERR_IO) hint = " (connection closed or timed out)";
    fail(E_TLS, "TLS error %d during %s%s", e, when, hint);
}

/* Run the engine until the handshake is done (app data can be sent). */
static void tls_handshake(struct conn *c) {
    br_ssl_engine_context *eng = &c->sc.eng;
    for (;;) {
        unsigned st = br_ssl_engine_current_state(eng);
        if (st & BR_SSL_CLOSED) tls_fail(c, "handshake");
        if (st & BR_SSL_SENDREC) {
            size_t len;
            unsigned char *buf = br_ssl_engine_sendrec_buf(eng, &len);
            int w = sock_write(&c->fd, buf, len);
            if (w < 0) { br_ssl_engine_close(eng); tls_fail(c, "handshake (write)"); }
            br_ssl_engine_sendrec_ack(eng, w);
            continue;
        }
        if (st & BR_SSL_SENDAPP) return;
        if (st & BR_SSL_RECVREC) {
            size_t len;
            unsigned char *buf = br_ssl_engine_recvrec_buf(eng, &len);
            int r = sock_read(&c->fd, buf, len);
            if (r < 0) fail(timed_out ? E_NET : E_TLS, "TLS handshake: %s", timed_out ? "timed out" : "connection closed");
            br_ssl_engine_recvrec_ack(eng, r);
            continue;
        }
        fail(E_TLS, "TLS handshake stalled (state 0x%x)", st);
    }
}

static void conn_open(struct conn *c, const struct url *u) {
    memset(c, 0, sizeof *c);
    c->fd = tcp_connect(u);
    c->tls = u->tls;
    if (!c->tls) return;
    c->ip_literal = strspn(u->host, "0123456789.") == strlen(u->host) || strchr(u->host, ':');
    br_ssl_client_init_full(&c->sc, &c->xc, KFETCH_TAs, KFETCH_TAs_NUM);
    if (opt_insecure) {
        c->xi.vtable = &x509_insecure_vtable;
        c->xi.inner = &c->xc;
        br_ssl_engine_set_x509(&c->sc.eng, &c->xi.vtable);
    }
    br_ssl_engine_set_buffer(&c->sc.eng, c->iobuf, sizeof c->iobuf, 1);
    br_ssl_client_reset(&c->sc, u->host, 0);
    double t0 = now_ms();
    tls_handshake(c);
    const br_ssl_session_parameters *sp = &c->sc.eng.session;
    vlog("TLS handshake %.0f ms: %s, cipher 0x%04X", now_ms() - t0, tls_version_name(sp->version), sp->cipher_suite);
    br_sslio_init(&c->io, &c->sc.eng, sock_read, &c->fd, sock_write, &c->fd);
}

static void conn_write(struct conn *c, const void *buf, size_t len) {
    if (c->tls) {
        if (br_sslio_write_all(&c->io, buf, len) < 0) tls_fail(c, "send");
    } else {
        const unsigned char *p = buf;
        while (len) {
            int w = sock_write(&c->fd, p, len);
            if (w < 0) fail(E_NET, "send failed: %s", strerror(errno));
            p += w;
            len -= w;
        }
    }
}

static void conn_flush(struct conn *c) {
    if (c->tls && br_sslio_flush(&c->io) < 0) tls_fail(c, "send");
}

/* Fill the read buffer; returns 0 at end of stream. */
static int conn_fill(struct conn *c) {
    if (c->eof) return 0;
    int r;
    if (c->tls) {
        r = br_sslio_read(&c->io, c->rbuf, sizeof c->rbuf);
        if (r < 0) {
            if (timed_out) fail(E_NET, "timed out waiting for data (-t %d)", opt_timeout);
            // Many servers close without close_notify; treat that as end of stream.
            int e = br_ssl_engine_last_error(&c->sc.eng);
            if (e != 0 && e != BR_ERR_IO) tls_fail(c, "receive");
            r = 0;
        }
    } else {
        do r = read(c->fd, c->rbuf, sizeof c->rbuf); while (r < 0 && errno == EINTR);
        if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) fail(E_NET, "timed out waiting for data (-t %d)", opt_timeout);
        if (r < 0) fail(E_NET, "receive failed: %s", strerror(errno));
    }
    if (r == 0) { c->eof = 1; return 0; }
    c->rpos = 0;
    c->rlen = r;
    return r;
}

static int conn_getc(struct conn *c) {
    if (c->rpos >= c->rlen && !conn_fill(c)) return -1;
    return c->rbuf[c->rpos++];
}

/* Read a CRLF-terminated line (CR/LF stripped). Returns length, or -1 at EOF. */
static int conn_line(struct conn *c, char *out, size_t n) {
    size_t i = 0;
    int ch;
    while ((ch = conn_getc(c)) >= 0 && ch != '\n')
        if (i + 1 < n) out[i++] = (char)ch;
    if (ch < 0 && i == 0) return -1;
    while (i && out[i - 1] == '\r') i--;
    out[i] = 0;
    return (int)i;
}

static void conn_close(struct conn *c) {
    if (c->tls) br_sslio_close(&c->io);
    close(c->fd);
}

/* ---------- HTTP ---------- */

struct response {
    int status;
    long long content_length;  // -1 = unknown
    int chunked;
    char location[2048];
};

static void out_write(FILE *out, const void *buf, size_t n) {
    if (n && fwrite(buf, 1, n, out) != n) fail(E_FILE, "write failed: %s", strerror(errno));
}

/* Copy n bytes (or until EOF if n < 0) from the connection to out. Returns bytes copied. */
static long long copy_body(struct conn *c, FILE *out, long long n) {
    long long done = 0;
    while (n < 0 || done < n) {
        if (c->rpos >= c->rlen && !conn_fill(c)) break;
        size_t avail = c->rlen - c->rpos;
        if (n >= 0 && (long long)avail > n - done) avail = (size_t)(n - done);
        if (out) out_write(out, c->rbuf + c->rpos, avail);
        c->rpos += avail;
        done += avail;
    }
    return done;
}

static void read_body(struct conn *c, struct response *r, FILE *out, const char *method) {
    if (!strcmp(method, "HEAD") || r->status == 204 || r->status == 304 || r->status / 100 == 1) return;
    if (r->chunked) {
        char line[256];
        for (;;) {
            if (conn_line(c, line, sizeof line) < 0) fail(E_PROTO, "connection closed inside chunked body");
            long long sz = strtoll(line, NULL, 16);
            if (sz == 0) {
                while (conn_line(c, line, sizeof line) > 0) {}  // trailers
                return;
            }
            if (copy_body(c, out, sz) != sz) fail(E_PROTO, "connection closed inside a chunk");
            conn_line(c, line, sizeof line);  // CRLF after chunk data
        }
    } else if (r->content_length >= 0) {
        long long got = copy_body(c, out, r->content_length);
        if (got != r->content_length)
            fail(E_PROTO, "body truncated: got %lld of %lld bytes", got, r->content_length);
    } else {
        copy_body(c, out, -1);
    }
}

static int is_redirect(int s) { return s == 301 || s == 302 || s == 303 || s == 307 || s == 308; }

struct header { struct header *next; const char *line; };

static int do_request(const struct url *u, const char *method, const struct header *hdrs, const char *data,
                      size_t data_len, FILE *out, struct response *r, int follow) {
    struct conn *c = calloc(1, sizeof *c);
    if (!c) fail(E_NET, "out of memory");
    conn_open(c, u);

    char req[4096];
    int defport = !strcmp(u->port, u->tls ? "443" : "80");
    int n = snprintf(req, sizeof req, "%s %s HTTP/1.1\r\nHost: %s%s%s\r\nUser-Agent: k4fetch/0.1\r\nAccept: */*\r\nConnection: close\r\n",
                     method, u->path, u->host, defport ? "" : ":", defport ? "" : u->port);
    int has_ct = 0;
    for (const struct header *h = hdrs; h; h = h->next) {
        if (!strncasecmp(h->line, "content-type:", 13)) has_ct = 1;
        n += snprintf(req + n, sizeof req - n, "%s\r\n", h->line);
    }
    if (data) {
        if (!has_ct) n += snprintf(req + n, sizeof req - n, "Content-Type: application/x-www-form-urlencoded\r\n");
        n += snprintf(req + n, sizeof req - n, "Content-Length: %zu\r\n", data_len);
    }
    n += snprintf(req + n, sizeof req - n, "\r\n");
    if (n >= (int)sizeof req) fail(E_USAGE, "request headers too long");
    conn_write(c, req, n);
    if (data) conn_write(c, data, data_len);
    conn_flush(c);
    vlog("sent %s %s", method, u->path);

    char line[4096];
    if (conn_line(c, line, sizeof line) < 0) fail(E_PROTO, "server closed the connection without a response");
    if (strncmp(line, "HTTP/1.", 7) || strlen(line) < 12) fail(E_PROTO, "bad status line: %.80s", line);
    memset(r, 0, sizeof *r);
    r->status = atoi(line + 9);
    r->content_length = -1;
    vlog("first byte: %s", line);
    int redirecting = follow && is_redirect(r->status);
    if (opt_include && !redirecting) fprintf(out, "%s\r\n", line);
    while (conn_line(c, line, sizeof line) > 0) {
        if (opt_include && !redirecting) fprintf(out, "%s\r\n", line);
        char *colon = strchr(line, ':');
        if (!colon) continue;
        *colon = 0;
        char *v = colon + 1;
        while (*v == ' ' || *v == '\t') v++;
        if (!strcasecmp(line, "content-length")) r->content_length = strtoll(v, NULL, 10);
        else if (!strcasecmp(line, "transfer-encoding") && strstr(v, "chunked")) r->chunked = 1;
        else if (!strcasecmp(line, "location")) snprintf(r->location, sizeof r->location, "%s", v);
    }
    if (opt_include && !redirecting) fprintf(out, "\r\n");
    if (r->chunked) r->content_length = -1;

    if (!redirecting) read_body(c, r, out, method);
    conn_close(c);
    free(c);
    return r->status;
}

static char *read_file(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) fail(E_FILE, "can't open %s: %s", path, strerror(errno));
    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    size_t r;
    while (buf && (r = fread(buf + n, 1, cap - n, f)) > 0) {
        n += r;
        if (n == cap) buf = realloc(buf, cap *= 2);
    }
    fclose(f);
    if (!buf) fail(E_FILE, "out of memory");
    *len = n;
    return buf;
}

static const char USAGE[] =
"usage: k4fetch [options] URL\n"
"       k4fetch --help | --version\n"
"\n"
"HTTP/HTTPS client with its own TLS 1.2 (BearSSL) and a small built-in set of root CAs.\n"
"HTTP/1.1, SNI, up to 5 redirects, chunked and Content-Length bodies, no compression, IPv4 only.\n"
"Needs a correct clock to validate certificates.\n"
"\n"
"Options:\n"
"  -o FILE   write the body to FILE (default stdout)\n"
"  -t SECS   connect / per-read timeout (default 20)\n"
"  -H HDR    extra request header, e.g. -H 'Accept: application/json' (repeatable)\n"
"  -X METH   request method (default GET, or POST with -d)\n"
"  -d DATA   request body (\"@file\" reads it from a file)\n"
"  -i        include the response status line and headers in the output\n"
"  -k        don't verify the certificate (debug only; can't bypass an expired one)\n"
"  -v        verbose: timings, TLS version/cipher and redirects on stderr\n"
"\n"
"Exit codes: 0 = 2xx, 1 = usage, 2 = DNS, 3 = connect/timeout/socket, 4 = TLS/certificate,\n"
"            5 = HTTP status not 2xx (body still written), 6 = bad response,\n"
"            7 = local file error, 8 = too many redirects\n";

static void usage(void) {
    fputs(USAGE, stderr);
    exit(E_USAGE);
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--version")) { printf("%s %s\n", "k4fetch", K4_VERSION); return 0; }
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) { fputs(USAGE, stdout); return 0; }
    const char *outpath = NULL, *method = NULL, *data = NULL, *urlarg = NULL;
    size_t data_len = 0;
    struct header *hdrs = NULL, **tail = &hdrs;
    t_start = now_ms();

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (a[0] != '-' || !a[1]) { if (urlarg) usage(); urlarg = a; continue; }
        if (!strcmp(a, "-i")) opt_include = 1;
        else if (!strcmp(a, "-k")) opt_insecure = 1;
        else if (!strcmp(a, "-v")) opt_verbose = 1;
        else if (i + 1 >= argc) usage();
        else if (!strcmp(a, "-o")) outpath = argv[++i];
        else if (!strcmp(a, "-t")) opt_timeout = atoi(argv[++i]);
        else if (!strcmp(a, "-X")) method = argv[++i];
        else if (!strcmp(a, "-d")) data = argv[++i];
        else if (!strcmp(a, "-H")) {
            struct header *h = calloc(1, sizeof *h);
            h->line = argv[++i];
            *tail = h;
            tail = &h->next;
        } else usage();
    }
    if (!urlarg || opt_timeout <= 0) usage();
    if (data) {
        if (data[0] == '@') data = read_file(data + 1, &data_len);
        else data_len = strlen(data);
    }
    if (!method) method = data ? "POST" : "GET";

    FILE *out = stdout;
    if (outpath && !(out = fopen(outpath, "wb"))) fail(E_FILE, "can't write %s: %s", outpath, strerror(errno));

    char cur[2048];
    snprintf(cur, sizeof cur, "%s", urlarg);
    struct response r;
    for (int hop = 0;; hop++) {
        struct url u;
        if (parse_url(cur, &u)) fail(E_USAGE, "bad URL: %s", cur);
        do_request(&u, method, hdrs, data, data_len, out, &r, 1);
        if (!is_redirect(r.status) || !r.location[0]) break;
        if (hop == 5) fail(E_REDIR, "too many redirects");
        char next[2048];
        if (resolve_location(&u, r.location, next, sizeof next)) fail(E_PROTO, "bad redirect: %s", r.location);
        vlog("redirect %d -> %s", r.status, next);
        snprintf(cur, sizeof cur, "%s", next);
        if (r.status == 303 || ((r.status == 301 || r.status == 302) && strcmp(method, "GET") && strcmp(method, "HEAD"))) {
            method = "GET";
            data = NULL;
            data_len = 0;
        }
    }
    if (fflush(out) || (out != stdout && fclose(out))) fail(E_FILE, "write failed: %s", strerror(errno));
    vlog("done: HTTP %d, total %.0f ms", r.status, now_ms() - t_start);
    return r.status / 100 == 2 ? E_OK : E_HTTP;
}
