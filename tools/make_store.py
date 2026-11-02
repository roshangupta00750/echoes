# Play Store screenshots (1920x1080, captioned in the game's own pixel font) and the 1024x500 feature graphic.
from PIL import Image, ImageDraw
import sys
R = sys.argv[1]; OUT = sys.argv[2]; FONT = sys.argv[3]
font = Image.open(FONT).convert("RGBA")
def text(img, s, x, y, scale, col, center=True):
    w = len(s) * 12 * scale
    if center: x = x - w // 2
    for i, ch in enumerate(s):
        code = ord(ch) - 32
        g = font.crop(((code % 16) * 12, (code // 16) * 16, (code % 16) * 12 + 12, (code // 16) * 16 + 16))
        g = g.resize((12 * scale, 16 * scale), Image.NEAREST)
        # tint: use the glyph's alpha (or brightness) as a mask
        a = g.split()[3]
        if a.getextrema() == (255, 255): a = g.convert("L")
        sh = Image.new("RGBA", g.size, (0, 0, 0, 200)); img.paste(sh, (x + i * 12 * scale + scale, y + scale * 2), a)
        tint = Image.new("RGBA", g.size, col + (255,)); img.paste(tint, (x + i * 12 * scale, y), a)
def shot(src, caption, out, sub=None, scale_cap=5):
    c = Image.new("RGBA", (1920, 1080), (5, 2, 12, 255))
    g = Image.open(src).convert("RGBA")
    if g.size[0] == g.size[1]:
        g = g.resize((860, 860), Image.NEAREST); c.paste(g, ((1920 - 860) // 2, 200))
    else:
        g = g.resize((1536, 864), Image.NEAREST); c.paste(g, (192, 196))
    text(c, caption, 960, 40, scale_cap, (102, 255, 255))
    if sub: text(c, sub, 960, 140, 2, (255, 160, 230))
    c.convert("RGB").save(out)
shots = [("l1.png", "LEVEL 1: JUST YOU.", "GRAB 5 SHARDS BEFORE TIME RUNS OUT", 5),
         ("swarm85.png", "LEVEL 8: EIGHT OF YOU.", "EVERY LEVEL, YOUR LAST RUN COMES BACK AS AN ECHO", 5),
         ("replay.png", "SEE WHICH PAST SELF GOT YOU.", "TOUCH ANY ECHO AND YOU'RE OUT", 5),
         ("ext.png", "EXTREME: THE NEWEST ECHO HUNTS.", "NORMAL, HARD AND EXTREME. DAILY RUN. 14 MISSIONS.", 4),
         ("card.png", "SHARE YOUR KNOT OF PAST SELVES.", "PLAY WITH FRIENDS ON THE SAME WI-FI: CAUGHT? BECOME A ZOMBIE", 4)]
for i, (src, cap, sub, sc) in enumerate(shots):
    shot(R + "/" + src, cap, "%s/screenshot_%d.png" % (OUT, i + 1), sub, sc)
# feature graphic: logo and line on the left, your trails on the right
fg = Image.new("RGBA", (1024, 500), (5, 2, 12, 255))
d = ImageDraw.Draw(fg)
for x in range(0, 1024, 32): d.line([(x, 0), (x, 500)], fill=(28, 12, 50, 255))
for y in range(0, 500, 32): d.line([(0, y), (1024, y)], fill=(28, 12, 50, 255))
card = Image.open(R + "/card.png").convert("RGBA")
knot = card.crop((36, 198, 1044, 675)).resize((400, 189), Image.LANCZOS)
fg.paste(knot, (600, 150), knot)
for k, col in [(3, (158, 97, 255)), (2, (255, 128, 26)), (1, (255, 64, 178))]:
    text(fg, "ECHOES", 40 + k * 4, 150 + k * 3, 6, col, center=False)
text(fg, "ECHOES", 40, 150, 6, (102, 255, 255), center=False)
text(fg, "YOUR PAST SELVES", 44, 270, 3, (255, 255, 255), center=False)
text(fg, "COME BACK.", 44, 322, 3, (255, 255, 255), center=False)
d = ImageDraw.Draw(fg)
sx, sy, r = 500, 340, 22
d.polygon([(sx, sy - r), (sx + r, sy), (sx, sy + r), (sx - r, sy)], fill=(255, 204, 64, 255), outline=(255, 250, 215, 255))
fg.convert("RGB").save(OUT + "/feature_graphic_1024x500.png")
print("store images written")
