// k4draw - draw on the Kindle 4 NT e-ink screen (or into a simulated screen file on any computer).
//
// K4 main boot uses Lab126's legacy einkfb driver (fb id "eink_fb"): 600x800, 8 bpp,
// line_length 600, and an inverted palette in memory (0 = white, 255 = black).
// The public interface of this tool uses normal gray: 0 = black, 255 = white.
// Run `k4draw --help` for the full usage (kept in USAGE below).

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef __linux__
#include <fcntl.h>
#include <linux/fb.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_BMP
#define STBI_ONLY_GIF
#define STBI_ONLY_PNM
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#include "../../third_party/stb/stb_image.h"
#define STB_TRUETYPE_IMPLEMENTATION
#include "../../third_party/stb/stb_truetype.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../../third_party/stb/stb_image_write.h"

#ifndef K4_VERSION
#define K4_VERSION "dev"  // set by tools/build.sh from git describe
#endif

// Lab126 einkfb ioctls (plain _IO: the argument is passed by value or as a raw pointer).
#define FBIO_EINK_UPDATE_DISPLAY      _IO('F', 0xdb)  // arg: fx
#define FBIO_EINK_UPDATE_DISPLAY_AREA _IO('F', 0xdd)  // arg: struct update_area *
#define FBIO_EINK_CLEAR_SCREEN        _IO('F', 0xe1)  // arg: 0 = screen + buffer

enum { FX_PARTIAL = 0, FX_FULL = 1, FX_FAST = 2, FX_SLOW = 3 };

struct update_area {
    int x1, y1, x2, y2;  // top-left, bottom-right
    int which_fx;
    uint8_t *buffer;     // NULL: take pixels from the framebuffer
};

#define DEFAULT_FONT "/usr/java/lib/fonts/Helvetica_LT_65_Medium.ttf"

static const char USAGE[] =
"usage: k4draw [-n] [-F|-a] <command> [args]  run one command\n"
"       k4draw [-n] [-F|-a] -                 run commands from stdin, one per line\n"
"       k4draw --help | --version\n"
"\n"
"Gray is 0 = black ... 255 = white (the panel shows about 16 levels). Screen: 600x800, origin top-left.\n"
"\n"
"Commands:\n"
"  info                                   print screen size, stride, mode (device/sim) and font\n"
"  clear [GRAY]                           fill the screen (default 255) and do a flashing full refresh\n"
"  fill X Y W H GRAY                      filled rectangle\n"
"  rect X Y W H GRAY [T]                  rectangle outline, T px thick (default 1)\n"
"  text X Y SIZE GRAY TEXT...             TrueType text; (X,Y) = top-left of the line, SIZE in px\n"
"  ctext CX Y SIZE GRAY TEXT...           like text, centred horizontally on CX\n"
"  font PATH                              TTF/TTC used by later text commands\n"
"  image PATH [X Y]                       PNG/JPEG/BMP/GIF/PGM, converted to gray, alpha blended\n"
"  export PATH.png [--panel]              save the screen as a gray PNG (--panel: quantize to 16 levels)\n"
"  refresh [partial|full|slow|fast] [X Y W H]   refresh the panel only (slow = always flashes)\n"
"\n"
"Options:\n"
"  -n   don't refresh the panel (change memory only)\n"
"  -F   refresh with a flashing full update instead of a partial one\n"
"  -a   auto: compare the screen before and after, refresh only the changed area partially, and flash\n"
"       when the changed box covers 60% of the screen, 30% of the pixels changed, or after 10 partials (ghosting)\n"
"Without -n, each command refreshes what it drew; in stdin mode one refresh covers everything at the end.\n"
"\n"
"Environment:\n"
"  K4DRAW_FB=FILE    simulate: draw into FILE (raw 600x800 screen, created white) instead of /dev/fb0.\n"
"                   Works on any computer; use export to look at it.\n"
"  K4DRAW_ROTATE=90  landscape: the screen is 800x600, drawn rotated for a device turned anticlockwise\n"
"                   (keypad on the right); 270 = turned clockwise. All commands and export use landscape coordinates.\n"
"  K4DRAW_TRACE=FILE in sim mode, append one line per refresh (time, fx, x y w h) for the simulator's viewer\n"
"  K4DRAW_FONTDIR=DIR use fonts from DIR when a command names one under /usr/java/lib/fonts/ (sim with the device's fonts)\n"
"  K4DRAW_FONT=PATH  default font (device: /usr/java/lib/fonts/Helvetica_LT_65_Medium.ttf;\n"
"                   sim: a system sans font if found)\n"
"  K4DRAW_DEBUG=1    print refresh timings to stderr\n"
"\n"
"Exit codes: 0 ok, 1 error (message on stderr), 2 usage.\n";

#ifdef __linux__
static int fb_fd = -1;
#endif
static const char *sim_path;  // K4DRAW_FB: simulated screen file
static uint8_t *fb;
static int W, H, stride;
static size_t fb_len;
// Landscape (K4DRAW_ROTATE=90 or 270): commands draw into a logical W x H canvas (800x600) and refresh() copies it,
// rotated, into the physical portrait framebuffer. 90 = device turned anticlockwise (keypad on the right), 270 = clockwise.
static int rot;
static uint8_t *phys;          // the real framebuffer (or sim file buffer) while fb points at the canvas
static int PW, PH, pstride;
static int opt_norefresh, opt_flash, opt_auto;
static uint8_t *snap;            // -a: copy of the screen when we started, to find what really changed
#define AUTO_FLASH_FRACTION 0.30 // -a: flash when this fraction of the pixels changed, or the changed box covers AUTO_FLASH_AREA
#define AUTO_FLASH_AREA 0.60     //     of the screen (a whole-screen redraw mostly rewrites white with white)...
#define AUTO_FLASH_EVERY 10      // ...or after this many partial refreshes in a row (ghosting)
#define AUTO_COUNTER "/var/run/k4draw.partials"
static const char *font_path;  // NULL until first use: default_font()
static unsigned char *font_data;
static stbtt_fontinfo font;

// Dirty rectangle accumulated over all drawing (x1,y1 inclusive; x2,y2 exclusive).
static int dx1 = 1 << 30, dy1 = 1 << 30, dx2 = -1, dy2 = -1;

static int clampi(int v, int lo, int hi);

static void die(const char *fmt, const char *arg) {
    fprintf(stderr, "k4draw: ");
    fprintf(stderr, fmt, arg);
    fprintf(stderr, "\n");
    exit(1);
}

static double now_ms(void) {
#ifdef __linux__
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
#else
    return clock() * 1000.0 / CLOCKS_PER_SEC;
#endif
}

static void sim_open(void) {
    W = 600, H = 800, stride = 600;
    fb_len = (size_t)stride * H;
    fb = calloc(1, fb_len);  // 0 = white
    if (!fb) die("out of memory%s", "");
    FILE *f = fopen(sim_path, "rb");
    if (f) {
        if (fread(fb, 1, fb_len, f) != fb_len) memset(fb, 0, fb_len);  // wrong size: start white
        fclose(f);
    }
}

static void sim_save(void) {
    FILE *f = fopen(sim_path, "wb");
    if (!f || fwrite(fb, 1, fb_len, f) != fb_len) die("can't write %s", sim_path);
    fclose(f);
}

static void fb_open(void) {
    if ((sim_path = getenv("K4DRAW_FB")) && *sim_path) { sim_open(); return; }
    sim_path = NULL;
#ifdef __linux__
    struct fb_fix_screeninfo fix;
    struct fb_var_screeninfo var;
    fb_fd = open("/dev/fb0", O_RDWR);
    if (fb_fd < 0) die("open /dev/fb0: %s (set K4DRAW_FB=file to simulate)", strerror(errno));
    if (ioctl(fb_fd, FBIOGET_FSCREENINFO, &fix) || ioctl(fb_fd, FBIOGET_VSCREENINFO, &var))
        die("fb info ioctl: %s", strerror(errno));
    if (var.bits_per_pixel != 8) die("unexpected bpp (want 8): %s", "");
    W = var.xres;
    H = var.yres;
    stride = fix.line_length;
    fb_len = (size_t)stride * var.yres_virtual;
    fb = mmap(NULL, fb_len, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd, 0);
    if (fb == MAP_FAILED) die("mmap: %s", strerror(errno));
#else
    die("no framebuffer on this system: set K4DRAW_FB=file to simulate%s", "");
#endif
}

// Logical (x,y) -> physical byte offset in the portrait framebuffer.
static inline size_t phys_at(int x, int y) {
    return rot == 90 ? (size_t)x * pstride + (PW - 1 - y) : (size_t)(PH - 1 - x) * pstride + y;
}

static void rotate_open(void) {
    const char *r = getenv("K4DRAW_ROTATE");
    if (!r || !*r || !strcmp(r, "0")) return;
    rot = atoi(r);
    if (rot != 90 && rot != 270) die("K4DRAW_ROTATE must be 0, 90 or 270 (got %s)", r);
    phys = fb, PW = W, PH = H, pstride = stride;
    W = PH, H = PW, stride = W;
    fb = malloc((size_t)stride * H);
    if (!fb) die("out of memory%s", "");
    for (int y = 0; y < H; y++)             // start from what is on the panel, so partial draws compose
        for (int x = 0; x < W; x++) fb[y * stride + x] = phys[phys_at(x, y)];
}

// Copy the logical region to the physical framebuffer (whole canvas when w or h <= 0).
static void rotate_sync(int x, int y, int w, int h) {
    if (!rot) return;
    int x0 = 0, y0 = 0, x1 = W, y1 = H;
    if (w > 0 && h > 0) x0 = clampi(x, 0, W), y0 = clampi(y, 0, H), x1 = clampi(x + w, 0, W), y1 = clampi(y + h, 0, H);
    for (int yy = y0; yy < y1; yy++)
        for (int xx = x0; xx < x1; xx++) phys[phys_at(xx, yy)] = fb[yy * stride + xx];
}

static void fb_close(void) {
    if (rot) { rotate_sync(0, 0, 0, 0); free(fb); fb = phys; }
    if (sim_path) { sim_save(); free(fb); return; }
#ifdef __linux__
    munmap(fb, fb_len);
    close(fb_fd);
#endif
}

// Default font: K4DRAW_FONT, else the device's Helvetica, else (sim) a common system sans font.
static const char *default_font(void) {
    static const char *candidates[] = {
        DEFAULT_FONT,
        "C:/Windows/Fonts/arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    };
    const char *env = getenv("K4DRAW_FONT");
    if (env && *env) return env;
    for (unsigned i = 0; i < sizeof candidates / sizeof candidates[0]; i++) {
        FILE *f = fopen(candidates[i], "rb");
        if (f) { fclose(f); return candidates[i]; }
    }
    return DEFAULT_FONT;
}

// Save the screen as a normal-gray PNG; --panel approximates the K4 panel's ~16 levels.
static void export_png(const char *path, int panel) {
    unsigned char *img = malloc((size_t)W * H);
    if (!img) die("out of memory%s", "");
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            int g = 255 - fb[y * stride + x];
            if (panel) g = (g / 17) * 17;  // 16 levels: 0, 17, ..., 255
            img[y * W + x] = (unsigned char)g;
        }
    if (!stbi_write_png(path, W, H, 1, img, W)) die("can't write %s", path);
    free(img);
}

static void mark(int x, int y, int w, int h) {
    if (x < dx1) dx1 = x;
    if (y < dy1) dy1 = y;
    if (x + w > dx2) dx2 = x + w;
    if (y + h > dy2) dy2 = y + h;
}

static int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }
// (clampi is declared above fb_close for rotate_sync)

// gray: 0 = black, 255 = white (normal). Memory is inverted.
static inline void put(int x, int y, int gray) {
    if ((unsigned)x < (unsigned)W && (unsigned)y < (unsigned)H) fb[y * stride + x] = 255 - gray;
}

static void fill(int x, int y, int w, int h, int gray) {
    int x0 = clampi(x, 0, W), y0 = clampi(y, 0, H), x1 = clampi(x + w, 0, W), y1 = clampi(y + h, 0, H);
    for (int yy = y0; yy < y1; yy++) memset(fb + yy * stride + x0, 255 - gray, x1 - x0);
    if (x1 > x0 && y1 > y0) mark(x0, y0, x1 - x0, y1 - y0);
}

static void rect(int x, int y, int w, int h, int gray, int t) {
    fill(x, y, w, t, gray);
    fill(x, y + h - t, w, t, gray);
    fill(x, y, t, h, gray);
    fill(x + w - t, y, t, h, gray);
}

static const char *mapped_font(const char *path) {
    static char buf[1024];
    const char *dir = getenv("K4DRAW_FONTDIR"), *pre = "/usr/java/lib/fonts/";
    if (!dir || !*dir || strncmp(path, pre, strlen(pre))) return path;
    snprintf(buf, sizeof buf, "%s/%s", dir, path + strlen(pre));
    return buf;
}

static void load_font(void) {
    if (font_data) return;
    if (!font_path) font_path = default_font();
    FILE *f = fopen(mapped_font(font_path), "rb");
    if (!f) die("can't open font %s", font_path);
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    font_data = malloc(n);
    if (!font_data || fread(font_data, 1, n, f) != (size_t)n) die("can't read font %s", font_path);
    fclose(f);
    if (!stbtt_InitFont(&font, font_data, stbtt_GetFontOffsetForIndex(font_data, 0)))
        die("bad font %s", font_path);
}

// Decode one UTF-8 code point; advances *s.
static int utf8_next(const char **s) {
    const unsigned char *p = (const unsigned char *)*s;
    int c = *p++, n = 0;
    if (c >= 0xf0) { c &= 0x07; n = 3; } else if (c >= 0xe0) { c &= 0x0f; n = 2; } else if (c >= 0xc0) { c &= 0x1f; n = 1; }
    while (n-- && (*p & 0xc0) == 0x80) c = (c << 6) | (*p++ & 0x3f);
    *s = (const char *)p;
    return c;
}

// Width in pixels of str at size (same advance/kerning as text()).
static int text_width(int size, const char *str) {
    load_font();
    float scale = stbtt_ScaleForPixelHeight(&font, size), w = 0;
    int prev = 0;
    while (*str) {
        int g = stbtt_FindGlyphIndex(&font, utf8_next(&str)), adv, lsb;
        if (prev) w += scale * stbtt_GetGlyphKernAdvance(&font, prev, g);
        stbtt_GetGlyphHMetrics(&font, g, &adv, &lsb);
        w += adv * scale;
        prev = g;
    }
    return (int)(w + 0.5f);
}

// Anti-aliased text, blended over what's already on screen.
static void text(int x, int y, int size, int gray, const char *str) {
    load_font();
    float scale = stbtt_ScaleForPixelHeight(&font, size);
    int ascent, descent, gap;
    stbtt_GetFontVMetrics(&font, &ascent, &descent, &gap);
    int base = y + (int)(ascent * scale + 0.5f);
    float pen = x;
    int prev = 0;
    while (*str) {
        int cp = utf8_next(&str);
        int g = stbtt_FindGlyphIndex(&font, cp);
        if (prev) pen += scale * stbtt_GetGlyphKernAdvance(&font, prev, g);
        int adv, lsb, gw, gh, ox, oy;
        stbtt_GetGlyphHMetrics(&font, g, &adv, &lsb);
        unsigned char *bm = stbtt_GetGlyphBitmapSubpixel(&font, scale, scale, pen - (int)pen, 0, g, &gw, &gh, &ox, &oy);
        int gx = (int)pen + ox, gy = base + oy;
        for (int j = 0; j < gh; j++)
            for (int i = 0; i < gw; i++) {
                int a = bm[j * gw + i];
                int px = gx + i, py = gy + j;
                if (!a || (unsigned)px >= (unsigned)W || (unsigned)py >= (unsigned)H) continue;
                int under = 255 - fb[py * stride + px];
                put(px, py, (gray * a + under * (255 - a)) / 255);
            }
        if (gw && gh) mark(gx, gy, gw, gh);
        stbtt_FreeBitmap(bm, NULL);
        pen += adv * scale;
        prev = g;
    }
}

static void image(const char *path, int x, int y) {
    int iw, ih, n;
    unsigned char *px = stbi_load(path, &iw, &ih, &n, 2);  // gray + alpha
    if (!px) die("can't load image: %s", stbi_failure_reason());
    for (int j = 0; j < ih; j++)
        for (int i = 0; i < iw; i++) {
            int sx = x + i, sy = y + j;
            if ((unsigned)sx >= (unsigned)W || (unsigned)sy >= (unsigned)H) continue;
            int g = px[(j * iw + i) * 2], a = px[(j * iw + i) * 2 + 1];
            int under = 255 - fb[sy * stride + sx];
            put(sx, sy, (g * a + under * (255 - a)) / 255);
        }
    mark(clampi(x, 0, W), clampi(y, 0, H), clampi(x + iw, 0, W) - clampi(x, 0, W), clampi(y + ih, 0, H) - clampi(y, 0, H));
    stbi_image_free(px);
}

// Refresh the panel. x,y,w,h < 0 / 0 means whole screen.
static int refresh(int fx, int x, int y, int w, int h) {
    int whole = w <= 0 || h <= 0 || (x <= 0 && y <= 0 && x + w >= W && y + h >= H);
    rotate_sync(x, y, whole ? 0 : w, whole ? 0 : h);
    if (sim_path) {  // simulated screen: nothing to refresh, but record what would have been refreshed
        const char *tr = getenv("K4DRAW_TRACE");
        if (tr && *tr) {
            FILE *f = fopen(tr, "a");
            if (f) {
                if (whole) fprintf(f, "%ld fx=%d 0 0 %d %d\n", (long)time(NULL), fx, W, H);
                else fprintf(f, "%ld fx=%d %d %d %d %d\n", (long)time(NULL), fx, clampi(x, 0, W), clampi(y, 0, H),
                             clampi(x + w, 0, W) - clampi(x, 0, W), clampi(y + h, 0, H) - clampi(y, 0, H));
                fclose(f);
            }
        }
        return 0;
    }
    double t0 = now_ms();
    int r = -1;
#ifdef __linux__
    if (whole) {
        r = ioctl(fb_fd, FBIO_EINK_UPDATE_DISPLAY, fx);
    } else {
        int x0 = clampi(x, 0, W), y0 = clampi(y, 0, H), x1 = clampi(x + w, 0, W), y1 = clampi(y + h, 0, H);
        if (rot == 90) { int t0_ = x0, t1_ = x1; x0 = PW - y1; x1 = PW - y0; y0 = t0_; y1 = t1_; }
        else if (rot == 270) { int t0_ = x0, t1_ = x1; x0 = y0; x1 = y1; y0 = PH - t1_; y1 = PH - t0_; }
        struct update_area a = { x0, y0, x1, y1, fx, NULL };
        r = ioctl(fb_fd, FBIO_EINK_UPDATE_DISPLAY_AREA, &a);
    }
#else
    (void)fx; (void)x; (void)y; (void)w; (void)h;
#endif
    if (r) fprintf(stderr, "k4draw: refresh ioctl failed: %s\n", strerror(errno));
    if (getenv("K4DRAW_DEBUG")) fprintf(stderr, "k4draw: refresh fx=%d %d,%d %dx%d took %.1f ms\n", fx, x, y, w, h, now_ms() - t0);
    return r;
}

static int parse_fx(const char *s) {
    if (!strcmp(s, "partial")) return FX_PARTIAL;
    if (!strcmp(s, "full")) return FX_FULL;
    if (!strcmp(s, "slow")) return FX_SLOW;
    if (!strcmp(s, "fast")) return FX_FAST;
    return -1;
}

#define NEED(n) do { if (argc < (n)) die("missing arguments for '%s'", cmd); } while (0)

// Runs one command; returns 1 if it already refreshed the panel itself.
static int run(int argc, char **argv) {
    const char *cmd = argv[0];
    if (!strcmp(cmd, "info")) {
        printf("%dx%d stride=%d mem=%zu mode=%s rotate=%d font=%s\n", W, H, stride, fb_len, sim_path ? "sim" : "device",
               rot, font_path ? font_path : default_font());
        return 1;
    } else if (!strcmp(cmd, "clear")) {
        int g = argc > 1 ? atoi(argv[1]) : 255;
        fill(0, 0, W, H, g);
        if (!opt_norefresh && !opt_auto) refresh(FX_SLOW, 0, 0, 0, 0);  // slow: always flashes, even if unchanged
        return 1;
    } else if (!strcmp(cmd, "fill")) {
        NEED(6);
        fill(atoi(argv[1]), atoi(argv[2]), atoi(argv[3]), atoi(argv[4]), atoi(argv[5]));
    } else if (!strcmp(cmd, "rect")) {
        NEED(6);
        rect(atoi(argv[1]), atoi(argv[2]), atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argc > 6 ? atoi(argv[6]) : 1);
    } else if (!strcmp(cmd, "text")) {
        NEED(6);
        char buf[1024] = "";
        for (int i = 5; i < argc; i++) {  // join the rest with spaces
            if (i > 5) strncat(buf, " ", sizeof buf - strlen(buf) - 1);
            strncat(buf, argv[i], sizeof buf - strlen(buf) - 1);
        }
        text(atoi(argv[1]), atoi(argv[2]), atoi(argv[3]), atoi(argv[4]), buf);
    } else if (!strcmp(cmd, "ctext")) {
        NEED(6);
        char buf[1024] = "";
        for (int i = 5; i < argc; i++) {
            if (i > 5) strncat(buf, " ", sizeof buf - strlen(buf) - 1);
            strncat(buf, argv[i], sizeof buf - strlen(buf) - 1);
        }
        int size = atoi(argv[3]);
        text(atoi(argv[1]) - text_width(size, buf) / 2, atoi(argv[2]), size, atoi(argv[4]), buf);
    } else if (!strcmp(cmd, "font")) {
        NEED(2);
        font_path = strdup(argv[1]);
        free(font_data);
        font_data = NULL;
        return 1;
    } else if (!strcmp(cmd, "image")) {
        NEED(2);
        image(argv[1], argc > 3 ? atoi(argv[2]) : 0, argc > 3 ? atoi(argv[3]) : 0);
    } else if (!strcmp(cmd, "export")) {
        NEED(2);
        export_png(argv[1], argc > 2 && !strcmp(argv[2], "--panel"));
        return 1;
    } else if (!strcmp(cmd, "refresh")) {
        int fx = argc > 1 ? parse_fx(argv[1]) : FX_PARTIAL;
        if (fx < 0) die("unknown refresh mode '%s' (partial|full|slow|fast)", argv[1]);
        if (argc > 5) refresh(fx, atoi(argv[2]), atoi(argv[3]), atoi(argv[4]), atoi(argv[5]));
        else refresh(fx, 0, 0, 0, 0);
        return 1;
    } else {
        die("unknown command '%s'", cmd);
    }
    return 0;
}

// -a: compare the screen with the snapshot taken at start; refresh only what changed, flash when a lot changed
// or after AUTO_FLASH_EVERY partial refreshes (e-ink ghosting). The counter lives in a tmpfs file (sim: next to the screen file).
static void auto_flush(void) {
    int x1 = W, y1 = H, x2 = -1, y2 = -1;
    long changed = 0;
    for (int y = 0; y < H; y++) {
        const uint8_t *a = fb + (size_t)y * stride, *b = snap + (size_t)y * stride;
        for (int x = 0; x < W; x++)
            if (a[x] != b[x]) {
                changed++;
                if (x < x1) x1 = x;
                if (x >= x2) x2 = x + 1;
                if (y < y1) y1 = y;
                if (y >= y2) y2 = y + 1;
            }
    }
    if (!changed) return;
    char cpath[1024];
    if (sim_path) snprintf(cpath, sizeof cpath, "%s.partials", sim_path);
    else snprintf(cpath, sizeof cpath, "%s", AUTO_COUNTER);
    int partials = 0;
    FILE *f = fopen(cpath, "r");
    if (f) { if (fscanf(f, "%d", &partials) != 1) partials = 0; fclose(f); }
    double area = (double)(x2 - x1) * (y2 - y1) / ((double)W * H);
    int flash = (double)changed / ((double)W * H) >= AUTO_FLASH_FRACTION || area >= AUTO_FLASH_AREA || partials + 1 >= AUTO_FLASH_EVERY;
    if (getenv("K4DRAW_DEBUG"))
        fprintf(stderr, "k4draw: auto: %ld px changed (%.0f%%), box %d,%d %dx%d, partials so far %d -> %s\n", changed,
                100.0 * changed / ((double)W * H), x1, y1, x2 - x1, y2 - y1, partials, flash ? "flash" : "partial");
    if (flash) { refresh(FX_SLOW, 0, 0, 0, 0); partials = 0; }
    else { refresh(FX_PARTIAL, x1, y1, x2 - x1, y2 - y1); partials++; }
    f = fopen(cpath, "w");
    if (f) { fprintf(f, "%d\n", partials); fclose(f); }
}

static void flush(void) {
    if (opt_norefresh) return;
    if (opt_auto) { auto_flush(); return; }
    if (dx2 < 0) return;
    if (opt_flash) refresh(FX_SLOW, 0, 0, 0, 0);
    else refresh(FX_PARTIAL, dx1, dy1, dx2 - dx1, dy2 - dy1);
}

// Split a line into argv; the text command keeps its remainder as one argument.
static int split(char *line, char **av, int max) {
    int n = 0;
    char *p = line;
    while (n < max) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p || *p == '\n' || *p == '#') break;
        if (n == 5 && (!strcmp(av[0], "text") || !strcmp(av[0], "ctext"))) {
            av[n++] = p;
            p[strcspn(p, "\r\n")] = 0;
            break;
        }
        av[n++] = p;
        p += strcspn(p, " \t\r\n");
        if (*p) *p++ = 0;
    }
    return n;
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--version")) { printf("%s %s\n", "k4draw", K4_VERSION); return 0; }
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) { fputs(USAGE, stdout); return 0; }
    int i = 1;
    for (; i < argc && argv[i][0] == '-' && argv[i][1]; i++) {
        if (!strcmp(argv[i], "-n")) opt_norefresh = 1;
        else if (!strcmp(argv[i], "-F")) opt_flash = 1;
        else if (!strcmp(argv[i], "-a")) opt_auto = 1;
        else die("unknown option %s", argv[i]);
    }
    if (i >= argc) {
        fputs(USAGE, stderr);
        return 2;
    }
    fb_open();
    rotate_open();
    if (opt_auto) {   // remember what the panel shows now; flush() diffs against it
        snap = malloc((size_t)stride * H);
        if (!snap) die("out of memory%s", "");
        memcpy(snap, fb, (size_t)stride * H);
    }
    if (!strcmp(argv[i], "-")) {
        char line[2048], *av[16];
        while (fgets(line, sizeof line, stdin)) {
            int n = split(line, av, 16);
            if (n) run(n, av);
        }
        flush();
    } else if (!run(argc - i, argv + i)) {
        flush();
    }
    fb_close();
    return 0;
}
