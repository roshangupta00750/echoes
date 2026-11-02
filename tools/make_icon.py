# ECHOES app icon: you (a white-hot cyan dot), three of your echoes trailing behind, and a gold shard.
# Drawn on a 108-pixel grid (the adaptive-icon grid) and scaled up with sharp pixels.
from PIL import Image, ImageDraw
import math, sys
N = 108
def layer_fg():
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def ring(cx, cy, r, w, col):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=w)
    def disc(cx, cy, r, col):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    # everything sits inside the 66-unit safe circle around the centre (54, 54)
    # echoes: hollow rings trailing up-right from the player, fading
    trail = [(66, 44, (255, 64, 178)), (74, 36, (255, 128, 26)), (80, 29, (158, 97, 255))]
    for i, (x, y, c) in enumerate(trail):
        a = 255 - i * 55
        disc(x, y, 7, c + (40,))
        ring(x, y, 6, 2, c + (a,))
    # the gold shard, top left
    sx, sy, sr = 37, 34, 9
    d.polygon([(sx, sy - sr), (sx + sr, sy), (sx, sy + sr), (sx - sr, sy)], fill=(255, 204, 64, 255), outline=(255, 250, 215, 255))
    # the comet trail behind the player, then its glow, then the player on top
    px, py = 50, 60
    for i in range(4, 0, -1):
        disc(px - 6 * i, py + 5 * i, 6 - i, (77, 255, 255, 130 - i * 25))
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0)); gd = ImageDraw.Draw(glow)
    for r, a in [(18, 34), (13, 70)]:
        gd.ellipse([px - r, py - r, px + r, py + r], fill=(77, 255, 255, a))
    im.alpha_composite(glow)
    d = ImageDraw.Draw(im)
    d.ellipse([px - 10, py - 10, px + 10, py + 10], fill=(255, 255, 255, 255))
    d.ellipse([px - 8, py - 8, px + 8, py + 8], fill=(77, 255, 255, 255))
    d.ellipse([px - 4, py - 4, px + 4, py + 4], fill=(255, 255, 255, 255))
    return im
def layer_bg():
    im = Image.new("RGBA", (N, N), (7, 2, 16, 255))
    d = ImageDraw.Draw(im)
    for x in range(0, N, 9): d.line([(x, 0), (x, N)], fill=(40, 18, 70, 255))
    for y in range(0, N, 9): d.line([(0, y), (N, y)], fill=(40, 18, 70, 255))
    return im
fg = layer_fg(); bg = layer_bg()
out = sys.argv[1]
fg.resize((432, 432), Image.NEAREST).save(out + "/icon_fg.png")
bg.resize((432, 432), Image.NEAREST).save(out + "/icon_bg.png")
full = Image.alpha_composite(bg, fg)
# the full icon crops in a little, as launchers do, so the art is large
crop = full.crop((9, 9, 99, 99))
crop.resize((192, 192), Image.NEAREST).save(out + "/icon.png")
crop.resize((512, 512), Image.NEAREST).save(sys.argv[2] + "/icon_512.png")
crop.resize((48, 48), Image.LANCZOS).save(sys.argv[2] + "/icon_48_preview.png")
print("icons written")
