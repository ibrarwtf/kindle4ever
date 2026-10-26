# Train rows (no|name|src|dst|arr|dep|pf) + the current time -> the 64x24 board text (see README.md for the design).
# usage: awk -v now=HH:MM -v date="MON 26 OCT" -v code=SC -v llabel="HYDERABAD / KACHEGUDA" -v rlabel="KAZIPET / NAGPUR" #            -v rightside="KZJ BPQ NGP ..." -v platforms="1 2 3" -f board.awk rows.txt
# Layout: header 3 rows, 3 platforms x 5 rows (exhaust, roof, windows, wheels, track), rule, COMING UP + 3 rows.
# Direction: a train whose destination is in "rightside" (or that ends here and came from the other side) moves right.
# Runs on busybox awk 1.7.2 (no length(array), no gensub, "or" is a built-in).
BEGIN {
    FS = "|"; W = 64; TW = W - 6; CW = 7
    nn = split(rightside, nl, " "); for (i = 1; i <= nn; i++) north[nl[i]] = 1
    np = split(platforms == "" ? "1 2 3" : platforms, PL, " ")
    if (code == "") code = "SC"
    split(now, hm, ":"); nowm = hm[1] * 60 + hm[2]
    ER[1] = "      ≋     "; ER[2] = " ┌───┬╨───┐ "; ER[3] = "─│ ▪ │  ▪ └┐"; ER[4] = " └─o──o───o┘"
    EL[1] = "     ≋      "; EL[2] = " ┌───╨┬───┐ "; EL[3] = "┌┘ ▪  │ ▪ │─"; EL[4] = "└o───o──o─┘ "
    ntr = 0
}
NF >= 7 { ntr++; no[ntr] = $1; nm[ntr] = $2; src[ntr] = $3; dst[ntr] = $4; arr[ntr] = $5; dep[ntr] = $6; pf[ntr] = $7 }

function mins(t,   a) { if (t == "") return -1; split(t, a, ":"); return a[1] * 60 + a[2] }
function rel(m) { if (m < 0) return -1; return (m >= nowm - 720) ? m : m + 1440 }   # past midnight -> tomorrow
function rep(s, k,   r) { r = ""; while (k-- > 0) r = r s; return r }
function ulen(s) { return length(s) }   # busybox awk counts bytes; the glyphs below are all 3-byte UTF-8, handled by padc()
function padc(s, w,   n) { n = w - cols(s); if (n > 0) s = s rep(" ", n); return s }
function cont(c) { return (c >= "\200" && c < "\300") }   # UTF-8 continuation byte?
function cols(s,   i, n) {   # display columns of a UTF-8 string (every multibyte char here is 1 column wide)
    n = 0
    for (i = 1; i <= length(s); i++) if (!cont(substr(s, i, 1))) n++
    return n
}
function center(s, w,   n, l) { n = w - cols(s); if (n <= 0) return s; l = int(n / 2); return rep(" ", l) s rep(" ", n - l) }
# state of train i: "on", "next", "left"; sets stime (the time shown under the platform number)
function state(i,   a, d) {
    a = rel(mins(arr[i])); d = rel(mins(dep[i]))
    if (a >= 0 && d >= 0) { if (a <= nowm && nowm < d) { stime = ""; return "on" } if (nowm >= d) { stime = dep[i]; return "left" } stime = arr[i]; return "next" }
    if (a < 0) { if (d >= 0 && nowm >= d) { stime = dep[i]; return "left" } if (d >= 0 && d - nowm <= 20) { stime = ""; return "on" } stime = dep[i]; return "next" }
    if (nowm >= a + 10) { stime = arr[i]; return "left" }
    if (nowm >= a) { stime = ""; return "on" }
    stime = arr[i]; return "next"
}
function right(i) { if (dst[i] == code) return !(src[i] in north); return (dst[i] in north) }
function key(i,   t) { t = arr[i] != "" ? arr[i] : dep[i]; return rel(mins(t)) }
# coaches(text, n, open_l, open_r) -> rows C[1..4] (blank, roof, windows, wheels), width n*CW+1
function coaches(text, n, ol, orr,   w, top, mid, bot, i) {
    w = n * CW + 1
    top = "┌"; mid = "│"; bot = "└"
    for (i = 1; i <= n; i++) { top = top rep("─", CW - 1) (i < n ? "┬" : "┐"); bot = bot "─o──o─" (i < n ? "┴" : "┘") }
    mid = "│" center(text, w - 2) "│"
    C[1] = rep(" ", w); C[2] = top; C[3] = mid; C[4] = bot
    if (ol) { C[2] = "─" cut1(C[2]); C[3] = " " cut1(C[3]); C[4] = "─" cut1(C[4]) }
    if (orr) { C[2] = cutl(C[2]) "─"; C[3] = cutl(C[3]) " "; C[4] = cutl(C[4]) "─" }
    return w
}
function cut1(s,   c, n) { c = substr(s, 1, 1); n = 1; if (c >= "\360") n = 4; else if (c >= "\340") n = 3; else if (c >= "\300") n = 2; return substr(s, n + 1) }   # drop the first UTF-8 char
function cutl(s,   i) { i = length(s); while (i > 1 && cont(substr(s, i, 1))) i--; return substr(s, 1, i - 1) }   # drop the last
# train(text, n, toward_right, state) -> rows R[1..5] of width TW
function train(text, n, tr, st,   w, i, pad, atr, fg, rh, ol, orr) {
    fg = (st == "left"); rh = (st == "next")
    ol = (rh && tr) || (fg && !tr); orr = (rh && !tr) || (fg && tr)
    w = coaches(text, n, ol, orr)
    if (st == "left") { for (i = 1; i <= 4; i++) R[i] = C[i] }
    else if (tr) { for (i = 1; i <= 4; i++) R[i] = C[i] ER[i]; w += 12 }
    else { for (i = 1; i <= 4; i++) R[i] = EL[i] C[i]; w += 12 }
    if (st == "on") pad = int((TW - w) / 2)
    else { atr = ((st == "next") != tr); pad = atr ? TW - w : 0 }
    if (pad < 0) pad = 0
    for (i = 1; i <= 4; i++) R[i] = padc(rep(" ", pad) R[i], TW)
    R[5] = rep("═", TW)
}
function platform(p, t,   i, lab) {
    lab[1] = "      "; lab[2] = "      "; lab[3] = "[" p "]   "; lab[4] = padc(t, 5) " "; lab[5] = "      "
    for (i = 1; i <= 5; i++) print lab[i] R[i]
}
END {
    print padc(code "  " toupper(name), W - 17) sprintf("%17s", date "  " now)
    print padc("◂ " llabel, W - cols(rlabel) - 2) rlabel " ▸"
    print rep("━", W)
    # pick one train per platform: on > next > left, earliest first; among "left" the latest
    for (i = 1; i <= ntr; i++) { st = state(i); S[i] = st; T[i] = stime; P[i] = (st == "on") ? 0 : (st == "next") ? 1 : 2 }
    for (i = 1; i <= ntr; i++) {
        p = pf[i]; ok = 0; for (k = 1; k <= np; k++) if (PL[k] == p) ok = 1; if (!ok) continue
        c = chosen[p]
        if (c == "" || P[i] < P[c] || (P[i] == 2 && P[c] == 2 && key(i) > key(c)) || (P[i] == P[c] && P[i] < 2 && key(i) < key(c))) chosen[p] = i
    }
    for (k = 1; k <= np; k++) {
        p = PL[k]; i = chosen[p]
        if (i == "") { for (k = 1; k <= 4; k++) R[k] = rep(" ", TW); R[5] = rep("═", TW); platform(p, ""); continue }
        drawn[i] = 1
        txt = no[i] " " substr(nm[i], 1, 16) "  " src[i] " ▸ " dst[i]
        n = int((cols(txt) + 2 + CW - 1) / CW); if (S[i] == "on") { if (n < 3) n = 3; if (n > 6) n = 6 } else if (n < 4) n = 4
        train(txt, n, right(i), S[i])
        platform(p, T[i])
    }
    print rep("━", W)
    print " COMING UP"
    # next 3 trains not drawn and not departed, by time (selection sort, few rows)
    shown = 0
    for (pass = 1; pass <= 3; pass++) {
        best = ""
        for (i = 1; i <= ntr; i++) if (!drawn[i] && !used[i] && S[i] != "left" && (best == "" || key(i) < key(best))) best = i
        if (best == "") break
        used[best] = 1; shown++
        ad = (arr[best] == "") ? "D" : "A"; tm = (arr[best] == "") ? dep[best] : arr[best]
        print substr("   " ad " " tm "  [" (pf[best] == "" ? "?" : pf[best]) "]  " no[best] " " padc(substr(nm[best], 1, 18), 18) " " src[best] " ▸ " dst[best], 1, 200)
    }
    while (shown++ < 3) print ""
}
