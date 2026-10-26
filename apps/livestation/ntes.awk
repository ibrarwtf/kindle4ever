# NTES Live Station HTML -> one line per train:  no|name|src|dst|arr|dep|pf
# arr/dep are the EXPECTED times (HH:MM), empty when the train starts/ends here. Runs on busybox awk 1.7.2.
# usage: awk -f ntes.awk page.html
BEGIN { RS = "<"; inrow = 0; n = 0 }
{
    # each record starts right after a "<": "tag attrs>text"; keep the text part
    i = index($0, ">"); if (i == 0) next
    # Fast path: until the table starts, only look for the "Platform" header cell (the page is ~290 KB, ~12k tags).
    if (!table) { if (index($0, "Platform") && substr($0, i + 1) ~ /^[ \t\r\n]*Platform[ \t\r\n]*$/) table = 1; next }
    txt = substr($0, i + 1)
    if (txt ~ /^[ \t\r\n]*$/) next
    gsub(/&nbsp;/, " ", txt); gsub(/&amp;/, "\\&", txt); gsub(/[ \t\r\n]+/, " ", txt)
    sub(/^ /, "", txt); sub(/ $/, "", txt)
    # rows start with a 1-2 digit serial number
    if (txt == "") next
    if (txt ~ /^[0-9][0-9]?$/ && (n == 0 || seen_coach)) { flush(); n = 1; seen_coach = 0; next }
    if (n == 0) next
    if (txt == "Coach Position") seen_coach = 1
    if (txt ~ /^Property of Indian Railways/) { flush(); table = 0; next }
    f[n++] = txt
}
END { flush() }

function flush(   no, name, route, src, dst, arr, dep, pf, k, t, toks, nt, j) {
    if (n < 12) { n = 0; return }
    no = f[1]; name = f[3]; route = f[4]
    if (no !~ /^[0-9][0-9][0-9][0-9][0-9]$/) { n = 0; return }
    src = route; sub(/^.*\(/, "", src); sub(/-.*$/, "", src)
    dst = route; sub(/^.*-/, "", dst); sub(/\).*$/, "", dst)
    # time tokens in order: [exp arr] [sched arr] [exp dep] [sched dep]...; "Source"/"Destination" stand in for a missing side
    nt = 0
    for (k = 5; k < n; k++) {
        t = f[k]
        if (t ~ /^[0-9][0-9]:[0-9][0-9]\*?$/ || t == "Source" || t == "Destination") toks[++nt] = t
    }
    arr = ""; dep = ""; j = 1
    if (nt >= 1) {
        if (toks[1] == "Source") j = 2
        else { arr = toks[1]; sub(/\*$/, "", arr); j = (nt >= 2 && toks[2] !~ /\*$/ && toks[2] ~ /^[0-9]/) ? 3 : 2 }
        if (j <= nt && toks[j] != "Destination" && toks[j] ~ /^[0-9]/) { dep = toks[j]; sub(/\*$/, "", dep) }
    }
    pf = ""
    for (k = n - 1; k >= 5; k--) if (f[k] ~ /^[0-9][0-9]?\*?$/) { pf = f[k]; sub(/\*$/, "", pf); break }
    printf "%s|%s|%s|%s|%s|%s|%s\n", no, name, src, dst, arr, dep, pf
    n = 0
}
