# Board text (64x24, from board.awk) -> k4draw commands for an 800x600 landscape screen (K4DRAW_ROTATE=90).
# Header bar with LIVE pill, direction line, the train grid drawn as real lines
# (box-drawing cells become 2 px fills, wheels become rings, windows become blocks), platform tags, "coming up" rows.
# usage: awk -v mono=/path/DejaVuSansMono.ttf -v title="SECUNDERABAD JN STATION" -v left="..." -v right="..." -f render.awk board.txt | K4DRAW_ROTATE=90 k4draw -F -
BEGIN {
    F = "/usr/java/lib/fonts/"; SANS = F "Helvetica_LT_65_Medium.ttf"; SANSB = F "Helvetica_LT_75_Bold.ttf"
    if (mono == "") mono = "/mnt/us/kindle4ever/apps/livestation/DejaVuSansMono.ttf"
    if (title == "") title = "LIVE STATION"
    W = 800; CW = 12; RH = 24; X0 = 16; Y0 = 90
    # box-drawing arms: up down left right (u = double up, for the exhaust stack)
    B["─"] = "0011"; B["│"] = "1100"; B["┌"] = "0101"; B["┐"] = "0110"; B["└"] = "1001"; B["┘"] = "1010"
    B["┬"] = "0111"; B["┴"] = "1011"; B["├"] = "1101"; B["┤"] = "1110"; B["┼"] = "1111"; B["╨"] = "u011"
    n = 0
}
{ L[++n] = $0 }

function fill(x, y, w, h, g) { printf "fill %d %d %d %d %d\n", x, y, w, h, g }
function txt(x, y, s, g, t) { printf "text %d %d %d %d %s\n", x, y, s, g, t }
function ctxt(x, y, s, g, t) { printf "ctext %d %d %d %d %s\n", x, y, s, g, t }
# small solid triangles (the device fonts have no arrow glyphs): h = height in px, (x, y) = top-left of the box
function arrow_r(x, y, h, g,   i) { for (i = 0; i < h / 2; i++) fill(x + i, y + i, 1, h - 2 * i, g) }
function arrow_l(x, y, h, g,   i) { for (i = 0; i < h / 2; i++) fill(x + h / 2 - 1 - i, y + i, 1, h - 2 * i, g) }
# split a UTF-8 string into display characters A[1..k]; returns k
function uchars(s,   i, c, k, ch, len) {
    k = 0; i = 1
    while (i <= length(s)) {
        c = substr(s, i, 1)
        if (c >= "\360") len = 4; else if (c >= "\340") len = 3; else if (c >= "\300") len = 2; else len = 1
        A[++k] = substr(s, i, len); i += len
    }
    return k
}
function cell(ch, cx, cy,   a, mx, my, top) {
    mx = cx + CW / 2; my = cy + RH / 2
    if (ch == "═") {          # track: two rails under the wheels of the row above, a sleeper tick every other cell
        top = cy - RH / 2 + 5
        fill(cx, top - 1, CW, 2, 0); fill(cx, top + 5, CW, 2, 0)
        if (int((cx - X0) / CW) % 2 == 0) fill(mx - 1, top + 1, 2, 4, 0)
        return 1
    }
    if (ch == "o") {          # wheel: octagonal ring r=5
        fill(mx - 5, my - 3, 10, 6, 0); fill(mx - 3, my - 5, 6, 10, 0); fill(mx - 3, my - 3, 6, 6, 255); return 1
    }
    if (ch == "▪") { fill(cx + 2, cy + 6, CW - 4, RH - 12, 0); return 1 }
    if (!(ch in B)) return 0
    a = B[ch]
    if (substr(a, 1, 1) == "u") { fill(mx - 3, cy, 1, RH / 2, 0); fill(mx + 1, cy, 1, RH / 2, 0) }
    else if (substr(a, 1, 1) == "1") fill(mx - 1, cy, 2, RH / 2, 0)
    if (substr(a, 2, 1) == "1") fill(mx - 1, my, 2, RH / 2, 0)
    if (substr(a, 3, 1) == "1") fill(cx, my - 1, CW / 2, 2, 0)
    if (substr(a, 4, 1) == "1") fill(mx, my - 1, CW / 2, 2, 0)
    return 1
}
END {
    print "clear"
    # header bar
    fill(0, 0, W, 58, 0)
    print "font " SANSB
    txt(16, 16, 24, 255, title)
    px = 16 + length(title) * 14.3 + 16; if (px > 560) px = 560     # LIVE pill after the title (bold 24 px is about 14.3 px per char)
    fill(px, 16, 72, 26, 255); fill(px + 2, 14, 68, 30, 255)
    fill(px + 10, 24, 10, 10, 0); fill(px + 12, 22, 6, 14, 0)
    txt(px + 26, 20, 16, 0, "LIVE")
    nh = split(L[1], hp, "  +"); clock = hp[nh]; date = hp[nh - 1]
    ctxt(W - 16 - 42, 4, 30, 255, clock); ctxt(W - 16 - 36, 37, 14, 255, date)
    # direction line: "◂  MANCHERIAL / HYDERABAD - - - - BALHARSHAH / NAGPUR  ▸"
    y = 76
    arrow_l(16, y - 5, 10, 0); txt(32, y - 8, 13, 0, left)
    rw = length(right) * 7.6; ctxt(W - 16 - 14 - rw / 2, y - 8, 13, 0, right); arrow_r(W - 16 - 8, y - 5, 10, 0)
    for (x = 32 + length(left) * 7.6 + 14; x < W - 16 - 14 - rw - 14; x += 14) fill(x, y - 1, 8, 2, 0)
    # platforms: text rows 4..18 (1-based), 3 x 5 rows; columns 7.. are the grid, 1..6 the label
    print "font " mono
    for (p = 0; p < 3; p++) for (r = 0; r < 5; r++) {
        line = L[4 + p * 5 + r]; k = uchars(line)
        cy = Y0 + (p * 5 + r) * RH
        for (c = 7; c <= k; c++) {
            ch = A[c]; if (ch == " ") continue
            cx = X0 + (c - 1) * CW
            if (!cell(ch, cx, cy)) txt(cx, cy + 2, 19, 0, ch)
        }
    }
    print "font " SANSB
    for (p = 0; p < 3; p++) {
        lab = substr(L[4 + p * 5 + 2], 1, 6); gsub(/[^0-9]/, "", lab)
        tm = L[4 + p * 5 + 3]; tm = substr(tm, 1, 6); gsub(/ /, "", tm)
        ly = Y0 + (p * 5 + 2) * RH
        fill(X0 - 4, ly - 4, 66, 30, 0); fill(X0 - 2, ly - 6, 62, 34, 0)
        ctxt(X0 + 29, ly - 1, 17, 255, "PF-" lab)
        if (tm != "") ctxt(X0 + 29, ly + 36, 15, 0, tm)
    }
    # coming up
    cy = Y0 + 15 * RH + 8
    fill(16, cy - 1, W - 32, 2, 0)
    fill(16, cy + 10, 88, 20, 0); txt(24, cy + 13, 13, 255, "COMING UP")
    for (i = 0; i < 3; i++) {
        line = L[21 + i]; sub(/^ +/, "", line); if (line == "") continue
        np = split(line, P, "  +"); if (np < 4) continue
        split(P[1], adt, " "); yy = cy + 40 + i * 25
        print "font " SANSB; txt(24, yy, 16, 90, adt[1]); txt(46, yy, 16, 0, adt[2])
        pfn = P[2]; gsub(/[^0-9?]/, "", pfn); txt(112, yy, 16, 0, "PF-" pfn)
        print "font " SANS; txt(172, yy, 16, 0, P[3])
        nr = split(P[4], RA, " "); txt(520, yy, 16, 0, RA[1])
        ax = 520 + length(RA[1]) * 11 + 6; arrow_r(ax, yy + 4, 10, 0); txt(ax + 14, yy, 16, 0, RA[nr])
    }
}
