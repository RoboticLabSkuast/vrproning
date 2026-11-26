"""
High-Detail Botanical PBR Texture, Sculpted 3D GLB Tool/Planter, and Spatial WAV Audio Generator
for VR Pruning (Meta Quest 3 Mixed Reality Tree Pruning App).
"""
import json
import math
import os
import struct
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
MOD_DIR = os.path.join(ROOT, "assets", "models")
AUD_DIR = os.path.join(ROOT, "assets", "audio")
os.makedirs(TEX_DIR, exist_ok=True)
os.makedirs(MOD_DIR, exist_ok=True)
os.makedirs(AUD_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Multi-Octave Periodic Noise & Normal Helpers
# ---------------------------------------------------------------------------
def value_noise_2d(h: int, w: int, scale_y: int, scale_x: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    grid = rng.random((scale_y, scale_x), dtype=np.float32)
    yy = np.linspace(0, scale_y, h, endpoint=False, dtype=np.float32)
    xx = np.linspace(0, scale_x, w, endpoint=False, dtype=np.float32)
    y0 = np.floor(yy).astype(np.int32) % scale_y
    x0 = np.floor(xx).astype(np.int32) % scale_x
    y1 = (y0 + 1) % scale_y
    x1 = (x0 + 1) % scale_x
    fy = (yy - np.floor(yy))[:, None]
    fx = (xx - np.floor(xx))[None, :]
    fy = fy * fy * (3.0 - 2.0 * fy)
    fx = fx * fx * (3.0 - 2.0 * fx)

    g00 = grid[np.ix_(y0, x0)]
    g10 = grid[np.ix_(y1, x0)]
    g01 = grid[np.ix_(y0, x1)]
    g11 = grid[np.ix_(y1, x1)]
    top = g00 * (1.0 - fx) + g01 * fx
    bot = g10 * (1.0 - fx) + g11 * fx
    return top * (1.0 - fy) + bot * fy


def fbm_2d(size: int, octaves: list, seed_base: int = 100) -> np.ndarray:
    out = np.zeros((size, size), dtype=np.float32)
    amp_sum = 0.0
    for i, (sy, sx, amp) in enumerate(octaves):
        out += value_noise_2d(size, size, sy, sx, seed_base + i * 37) * amp
        amp_sum += amp
    return out / max(amp_sum, 1e-6)


def height_to_normal(height: np.ndarray, strength: float = 5.0) -> Image.Image:
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    nx = -dx
    ny = -dy
    nz = np.ones_like(height)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    rgb = np.stack([(nx * inv_len * 0.5 + 0.5), (ny * inv_len * 0.5 + 0.5), (nz * inv_len * 0.5 + 0.5)], axis=-1)
    return Image.fromarray(np.clip(rgb * 255.0, 0, 255).astype(np.uint8), "RGB")


def save_gray(arr: np.ndarray, name: str):
    Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), "L").save(os.path.join(TEX_DIR, name))


# ---------------------------------------------------------------------------
# 1. Realistic High-Frequency Botanical Bark & Cut-Wood PBR Textures
# ---------------------------------------------------------------------------
def generate_bark(name_prefix: str, base_dark, base_mid, base_light, lichen_col,
                  vertical_stretch: float, fissure_depth: float, lenticel_strength: float, seed: int):
    S = 768
    # Domain-warped vertical bark plates & deep dark fissures
    warp_x = fbm_2d(S, [(6, 6, 1.0), (14, 14, 0.55), (28, 28, 0.25)], seed)
    # Shift coordinates organically along Y/X using integer roll approximation via smooth interpolation
    plates = fbm_2d(S, [
        (4, int(18 * vertical_stretch), 1.0),
        (8, int(36 * vertical_stretch), 0.75),
        (16, int(72 * vertical_stretch), 0.52),
        (32, int(128 * vertical_stretch), 0.34),
        (64, int(220 * vertical_stretch), 0.22),
    ], seed + 19)
    micro_fiber = fbm_2d(S, [(48, 128, 0.6), (96, 256, 0.45), (192, 384, 0.30)], seed + 71)

    # Sharp ridge-and-crevice profile (ridged multifractal look)
    raw = plates * 0.78 + warp_x * 0.22
    ridged = 1.0 - np.abs(raw * 2.0 - 1.0)
    crevices = np.power(np.clip(1.0 - ridged, 0.0, 1.0), 1.75)
    height = np.clip(ridged * 0.72 + micro_fiber * 0.28 - crevices * fissure_depth, 0.0, 1.0)

    # Rich color gradient with dark ambient occlusion inside deep bark cracks
    t = np.clip(height, 0.0, 1.0)[..., None]
    c_dark = np.array(base_dark, dtype=np.float32)
    c_mid = np.array(base_mid, dtype=np.float32)
    c_light = np.array(base_light, dtype=np.float32)

    col = np.where(t < 0.42,
                   c_dark + (c_mid - c_dark) * (t / 0.42),
                   c_mid + (c_light - c_mid) * ((t - 0.42) / 0.58))
    # Darken crevices (AO)
    col *= (1.0 - crevices[..., None] * 0.48)

    # Natural horizontal lenticels (like apple/cherry/maple bark)
    if lenticel_strength > 0.01:
        lent = fbm_2d(S, [(96, 8, 1.0), (192, 16, 0.6)], seed + 133)
        l_band = np.clip((lent - 0.66) * 6.5, 0.0, 1.0) * lenticel_strength
        col = col * (1.0 - l_band[..., None] * 0.45) + (c_light * 1.12) * (l_band[..., None] * 0.45)
        height = np.clip(height + l_band * 0.14, 0.0, 1.0)

    # Subtle moss/lichen flecks on raised plates
    lichen_n = fbm_2d(S, [(12, 12, 1.0), (36, 36, 0.6), (96, 96, 0.35)], seed + 211)
    l_mask = np.clip((lichen_n - 0.65) * 5.2, 0.0, 0.75) * np.clip((height - 0.42) * 2.2, 0.0, 1.0)
    col = col * (1.0 - l_mask[..., None]) + np.array(lichen_col, dtype=np.float32) * l_mask[..., None]

    Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").save(
        os.path.join(TEX_DIR, f"{name_prefix}_albedo.png"))
    height_to_normal(height, strength=7.5).save(os.path.join(TEX_DIR, f"{name_prefix}_normal.png"))
    rough = np.clip(0.96 - height * 0.16 + crevices * 0.06, 0.70, 0.98)
    save_gray(rough, f"{name_prefix}_roughness.png")


def generate_wood_cut(name: str, dead: bool = False):
    S = 768
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx = S * 0.5
    cy = S * 0.5
    dx = (xx - cx) / (S * 0.5)
    dy = (yy - cy) / (S * 0.5)
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)

    wobble = fbm_2d(S, [(8, 8, 1.0), (24, 24, 0.45), (64, 64, 0.2)], 77 if not dead else 177)
    r_w = r + (wobble - 0.5) * 0.04

    # Sharp crisp concentric annual growth rings
    rings = np.power(0.5 + 0.5 * np.sin(r_w * 72.0 + wobble * 4.2), 3.0)
    fine_rings = 0.5 + 0.5 * np.sin(r_w * 190.0 + wobble * 6.0)
    rays = np.power(0.5 + 0.5 * np.sin(ang * 56.0 + wobble * 2.5), 5.0) * 0.22
    saw_marks = (0.5 + 0.5 * np.sin((xx * 0.7 + yy * 0.3) * 0.45)) * 0.05

    if not dead:
        heart = np.array([154, 108, 64], dtype=np.float32)
        sap = np.array([234, 208, 158], dtype=np.float32)
        ring_dark = np.array([128, 86, 48], dtype=np.float32)
        cambium = np.array([118, 174, 72], dtype=np.float32)
        bark_rim = np.array([62, 46, 34], dtype=np.float32)
    else:
        heart = np.array([96, 84, 72], dtype=np.float32)
        sap = np.array([138, 126, 110], dtype=np.float32)
        ring_dark = np.array([68, 58, 48], dtype=np.float32)
        cambium = np.array([92, 84, 72], dtype=np.float32)
        bark_rim = np.array([50, 44, 38], dtype=np.float32)

    t_sap = np.clip((r_w - 0.28) / 0.46, 0.0, 1.0)[..., None]
    col = heart * (1.0 - t_sap) + sap * t_sap
    ring_mix = np.clip(rings * 0.34 + fine_rings * 0.08, 0.0, 0.45)[..., None]
    col = col * (1.0 - ring_mix) + ring_dark * ring_mix
    col += rays[..., None] * 26.0 - saw_marks[..., None] * 18.0

    if dead:
        crack_ang = np.abs(np.sin(ang * 6.0 + wobble * 0.8))
        crack = np.clip((0.07 - crack_ang) * 16.0, 0.0, 1.0) * np.clip(r * 1.4, 0.0, 1.0)
        col *= (1.0 - crack[..., None] * 0.76)

    c_mask = np.exp(-((r_w - 0.895) / 0.026) ** 2)[..., None]
    col = col * (1.0 - c_mask) + cambium * c_mask
    b_mask = np.clip((r_w - 0.925) / 0.035, 0.0, 1.0)[..., None]
    col = col * (1.0 - b_mask) + bark_rim * b_mask

    Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").save(
        os.path.join(TEX_DIR, f"{name}_albedo.png"))
    h = (1.0 - rings * 0.30) + rays * 0.22 + wobble * 0.20 + saw_marks * 0.3
    height_to_normal(h, strength=3.4).save(os.path.join(TEX_DIR, f"{name}_normal.png"))


# ---------------------------------------------------------------------------
# 2. Realistic Botanical Leaf Cluster Sprites (Bezier Curved + AO Shaded)
# ---------------------------------------------------------------------------
def draw_realistic_leaf(canvas: Image.Image, cx, cy, angle, length, width,
                        col_dark, col_mid, col_tip, col_vein, serrations=9, curl=0.0):
    S = canvas.width
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    steps = 36
    pts_left = []
    pts_right = []
    ca, sa = math.cos(angle), math.sin(angle)
    px, py = -sa, ca

    for i in range(steps + 1):
        t = i / steps
        # Natural botanical ovate-lanceolate curve
        w_t = math.sin(math.pow(t, 0.65) * math.pi) * width * (1.0 - 0.16 * t)
        if serrations > 0 and 0.10 < t < 0.94:
            tooth = 0.085 * width * math.sin(t * serrations * math.pi * 2.0)
            w_t = max(1.0, w_t + tooth)
        bend = curl * (t * t) * width * 0.55
        bx = cx + ca * (t * length) + px * bend
        by = cy + sa * (t * length) + py * bend
        pts_left.append((bx + px * w_t, by + py * w_t))
        pts_right.append((bx - px * w_t * (1.0 - curl * 0.15), by - py * w_t * (1.0 - curl * 0.15)))

    # Petiole stalk
    pet_x = cx - ca * (length * 0.12)
    pet_y = cy - sa * (length * 0.12)
    draw.line([(pet_x, pet_y), (cx, cy)], fill=col_vein, width=max(2, int(width * 0.11)))

    # Base leaf silhouette + sunlit half + tip highlight for 3D folded blade depth
    poly = pts_left + list(reversed(pts_right))
    draw.polygon(poly, fill=col_mid)

    # Shaded left half vs sunlit right half across midrib (gives crisp 3D folded V-shape!)
    mid_spine = [
        (cx + ca * (i / steps * length) + px * (curl * (i / steps) ** 2 * width * 0.55),
         cy + sa * (i / steps * length) + py * (curl * (i / steps) ** 2 * width * 0.55))
        for i in range(steps + 1)
    ]
    draw.polygon(pts_left + list(reversed(mid_spine)), fill=col_dark)

    # Smooth sunlit gradient from stem base to tip (zero sharp polygon seam!)
    tip_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tip_draw = ImageDraw.Draw(tip_layer)
    tip_poly = pts_left[steps // 3:] + list(reversed(pts_right[steps // 3:]))
    tip_draw.polygon(tip_poly, fill=col_tip)
    tip_layer = tip_layer.filter(ImageFilter.GaussianBlur(8.0))
    # Mask blurred highlight back cleanly inside leaf alpha
    leaf_alpha = layer.split()[3]
    t_alpha = Image.fromarray(np.minimum(np.array(tip_layer.split()[3]), np.array(leaf_alpha)).astype(np.uint8), "L")
    tip_layer.putalpha(t_alpha)
    layer.alpha_composite(tip_layer)
    draw = ImageDraw.Draw(layer)

    # Midrib + delicate curved lateral veins
    draw.line(mid_spine, fill=col_vein, width=max(2, int(width * 0.07)))
    for v in range(1, 7):
        vt = 0.14 + v * 0.125
        idx = min(steps, int(vt * steps))
        vx, vy = mid_spine[idx]
        vw = math.sin(math.pow(vt, 0.65) * math.pi) * width * 0.78
        for side in (-1, 1):
            mx = vx + ca * (length * 0.05) + px * side * (vw * 0.5)
            my = vy + sa * (length * 0.05) + py * side * (vw * 0.5)
            ex = vx + ca * (length * 0.12) + px * side * (vw * 0.92)
            ey = vy + sa * (length * 0.12) + py * side * (vw * 0.92)
            draw.line([(vx, vy), (mx, my), (ex, ey)], fill=col_vein, width=max(1, int(width * 0.038)))

    # Soft drop shadow underneath overlapping leaves for lush botanical depth
    shadow_alpha = layer.split()[3].filter(ImageFilter.GaussianBlur(5.0))
    shadow = Image.new("RGBA", (S, S), (12, 20, 8, 0))
    shadow.putalpha(shadow_alpha.point(lambda a: int(a * 0.36)))
    canvas.alpha_composite(shadow, dest=(3, 5))
    canvas.alpha_composite(layer)


def draw_maple_leaf(canvas: Image.Image, cx, cy, angle, size, c_dark, c_mid, c_tip, c_vein):
    lobe_angles = [-1.20, -0.60, 0.0, 0.60, 1.20]
    lobe_scales = [0.54, 0.86, 1.0, 0.86, 0.54]
    for la, ls in zip(lobe_angles, lobe_scales):
        draw_realistic_leaf(canvas, cx, cy, angle + la, size * ls, size * 0.15 * ls,
                            c_dark, c_mid, c_tip, c_vein, serrations=7)


def generate_foliage_cluster(filename: str, species: str):
    S = 768
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = np.random.default_rng({"apple": 111, "maple": 222, "olive": 333, "dead": 444}[species])

    stem_col = (84, 62, 42, 255) if species != "dead" else (76, 66, 56, 255)
    twig_branches = [
        ((384, 745), (384, 340)),
        ((384, 610), (210, 440)),
        ((384, 540), (565, 385)),
        ((384, 435), (245, 225)),
        ((384, 395), (535, 205)),
        ((384, 340), (384, 120)),
        ((245, 225), (155, 165)),
        ((535, 205), (620, 155)),
    ]
    for p0, p1 in twig_branches:
        draw.line([p0, p1], fill=stem_col, width=9)

    # Layer back-to-front (lower/inner darker leaves first, outer sunlit leaves on top!)
    anchors = [
        (384, 480, -2.25, 0.82), (384, 470, -0.88, 0.82), (305, 520, -2.55, 0.84), (465, 510, -0.60, 0.84),
        (225, 450, -2.85, 0.90), (265, 415, -2.40, 0.92), (185, 395, -3.00, 0.88),
        (555, 395, -0.32, 0.90), (515, 375, -0.75, 0.92), (595, 345, -0.15, 0.88),
        (325, 345, -2.05, 0.95), (445, 340, -1.08, 0.95), (384, 375, -1.57, 0.96),
        (250, 235, -2.35, 1.00), (195, 210, -2.65, 0.98), (155, 175, -2.85, 0.95), (295, 190, -2.00, 1.02),
        (525, 215, -0.80, 1.00), (585, 190, -0.50, 0.98), (625, 165, -0.30, 0.95), (475, 175, -1.10, 1.02),
        (355, 185, -1.85, 1.05), (415, 185, -1.28, 1.05), (384, 130, -1.57, 1.08),
    ]

    for ax, ay, ang, light_mul in anchors:
        jitter_a = ang + rng.uniform(-0.20, 0.20)
        if species == "apple":
            g = int(rng.integers(104, 142) * light_mul)
            dark = (int(g * 0.36), int(g * 0.82), int(g * 0.22), 255)
            mid = (int(g * 0.46), min(255, g), int(g * 0.26), 255)
            tip = (int(g * 0.62), min(255, int(g * 1.18)), int(g * 0.32), 255)
            vein = (int(g * 0.72), min(255, int(g * 1.24)), int(g * 0.38), 255)
            draw_realistic_leaf(img, ax, ay, jitter_a, rng.uniform(108, 138), rng.uniform(42, 54),
                                dark, mid, tip, vein, serrations=10)
        elif species == "maple":
            r = int(rng.integers(138, 184) * light_mul)
            dark = (int(r * 0.74), int(r * 0.14), int(r * 0.11), 255)
            mid = (min(255, r), int(r * 0.22), int(r * 0.16), 255)
            tip = (min(255, int(r * 1.22)), int(r * 0.34), int(r * 0.18), 255)
            vein = (min(255, int(r * 1.25)), int(r * 0.48), int(r * 0.24), 255)
            draw_maple_leaf(img, ax, ay, jitter_a, rng.uniform(106, 140), dark, mid, tip, vein)
        elif species == "olive":
            g = int(rng.integers(108, 134) * light_mul)
            dark = (int(g * 0.54), int(g * 0.82), int(g * 0.48), 255)
            mid = (int(g * 0.68), min(255, g), int(g * 0.58), 255)
            tip = (int(g * 0.86), min(255, int(g * 1.15)), int(g * 0.76), 255)
            vein = (min(255, int(g * 1.08)), min(255, int(g * 1.25)), min(255, int(g * 0.96)), 255)
            draw_realistic_leaf(img, ax, ay, jitter_a, rng.uniform(118, 152), rng.uniform(19, 27),
                                dark, mid, tip, vein, serrations=0)
        elif species == "dead":
            b = int(rng.integers(92, 126) * light_mul)
            dark = (int(b * 0.78), int(b * 0.54), int(b * 0.32), 255)
            mid = (b, int(b * 0.70), int(b * 0.42), 255)
            tip = (int(b * 0.85), int(b * 0.58), int(b * 0.34), 255)
            vein = (int(b * 0.60), int(b * 0.42), int(b * 0.24), 255)
            draw_realistic_leaf(img, ax, ay, jitter_a, rng.uniform(86, 114), rng.uniform(22, 32),
                                dark, mid, tip, vein, serrations=5, curl=0.55)

    # Organic leaf surface micro-variation
    arr = np.array(img, dtype=np.float32)
    shade = fbm_2d(S, [(24, 24, 1.0), (64, 64, 0.5)], 303)[..., None]
    arr[..., :3] *= (0.88 + shade * 0.24)
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    out.save(os.path.join(TEX_DIR, filename))

    alpha_soft = np.array(out.split()[3].filter(ImageFilter.GaussianBlur(3.5)), dtype=np.float32) / 255.0
    leaf_h = alpha_soft * 0.7 + shade[..., 0] * 0.3
    height_to_normal(leaf_h, strength=3.5).save(os.path.join(TEX_DIR, filename.replace("_albedo.png", "_normal.png")))


def generate_misc_textures():
    S = 512
    clay_h = fbm_2d(S, [(8, 8, 1.0), (24, 24, 0.5), (64, 64, 0.3)], 401)
    yy = np.linspace(0, 1, S, dtype=np.float32)[:, None]
    wheel_ribs = 0.5 + 0.5 * np.sin(yy * 48.0)
    h_tc = clay_h * 0.78 + wheel_ribs * 0.22
    efflo = np.clip((fbm_2d(S, [(6, 6, 1.0), (20, 20, 0.6)], 409) - 0.64) * 4.5, 0.0, 0.45)
    c_tc = np.stack([
        172 + h_tc * 34 + efflo * 45,
        88 + h_tc * 22 + efflo * 52,
        56 + h_tc * 16 + efflo * 48
    ], axis=-1)
    Image.fromarray(np.clip(c_tc, 0, 255).astype(np.uint8), "RGB").save(os.path.join(TEX_DIR, "terracotta_albedo.png"))
    height_to_normal(h_tc, strength=3.4).save(os.path.join(TEX_DIR, "terracotta_normal.png"))

    soil_h = fbm_2d(S, [(12, 12, 0.6), (32, 32, 0.8), (80, 80, 0.5)], 501)
    mulch_bits = np.clip((fbm_2d(S, [(24, 8, 1.0), (48, 16, 0.6)], 509) - 0.56) * 4.0, 0.0, 1.0)
    c_soil = np.stack([
        38 + soil_h * 32 + mulch_bits * 58,
        28 + soil_h * 24 + mulch_bits * 38,
        19 + soil_h * 16 + mulch_bits * 22
    ], axis=-1)
    Image.fromarray(np.clip(c_soil, 0, 255).astype(np.uint8), "RGB").save(os.path.join(TEX_DIR, "soil_albedo.png"))
    height_to_normal(soil_h * 0.65 + mulch_bits * 0.35, strength=5.5).save(os.path.join(TEX_DIR, "soil_normal.png"))

    S2 = 256
    grain = fbm_2d(S2, [(64, 4, 1.0), (128, 8, 0.5)], 601)
    c_st = np.stack([182 + grain * 44, 188 + grain * 44, 196 + grain * 42], axis=-1)
    Image.fromarray(np.clip(c_st, 0, 255).astype(np.uint8), "RGB").save(os.path.join(TEX_DIR, "steel_albedo.png"))
    save_gray(0.18 + grain * 0.16, "steel_roughness.png")

    yy2, xx2 = np.mgrid[0:S2, 0:S2].astype(np.float32)
    knurl = np.abs(np.sin(xx2 * 0.65) * np.sin(yy2 * 0.65))
    c_gr = np.stack([165 + knurl * 25, 38 + knurl * 12, 32 + knurl * 10], axis=-1)
    Image.fromarray(np.clip(c_gr, 0, 255).astype(np.uint8), "RGB").save(os.path.join(TEX_DIR, "grip_albedo.png"))
    height_to_normal(knurl, strength=4.0).save(os.path.join(TEX_DIR, "grip_normal.png"))

    Sh = 256
    yy3, xx3 = np.mgrid[0:Sh, 0:Sh].astype(np.float32)
    dist = np.sqrt(((xx3 - Sh * 0.5) / (Sh * 0.48)) ** 2 + ((yy3 - Sh * 0.5) / (Sh * 0.48)) ** 2)
    alpha = np.power(np.clip(1.0 - dist, 0.0, 1.0), 2.2) * 0.72
    sh_rgba = np.zeros((Sh, Sh, 4), dtype=np.uint8)
    sh_rgba[..., 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)
    Image.fromarray(sh_rgba, "RGBA").save(os.path.join(TEX_DIR, "contact_shadow.png"))

    ic = Image.new("RGBA", (432, 432), (24, 52, 38, 255))
    d = ImageDraw.Draw(ic)
    d.ellipse([26, 26, 406, 406], fill=(34, 78, 52, 255), outline=(124, 198, 112, 255), width=10)
    draw_realistic_leaf(ic, 190, 270, -0.95, 175, 58,
                        (70, 148, 56, 255), (88, 178, 72, 255), (146, 218, 96, 255), (205, 240, 165, 255))
    d = ImageDraw.Draw(ic)
    d.polygon([(125, 330), (215, 210), (275, 110), (240, 195), (155, 345)], fill=(215, 224, 232, 255))
    d.polygon([(305, 330), (225, 215), (175, 115), (205, 200), (275, 345)], fill=(204, 62, 48, 255))
    d.ellipse([205, 198, 233, 226], fill=(224, 178, 72, 255))
    ic.save(os.path.join(TEX_DIR, "app_icon_432.png"))
    ic.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(TEX_DIR, "app_icon_192.png"))

    # Botanical imbricate bud-scale texture (V=0 tip, V=1 base)
    Sb = 256
    yyb, xxb = np.mgrid[0:Sb, 0:Sb].astype(np.float32)
    u_b = xxb / float(Sb)
    v_b = yyb / float(Sb)
    # Layered overlapping diamond bud scales
    scale1 = np.sin(u_b * math.pi * 6.0) * 0.5 + 0.5
    scale2 = np.sin((u_b + 0.083) * math.pi * 6.0) * 0.5 + 0.5
    row = v_b * 7.0
    row_i = np.floor(row)
    row_f = row - row_i
    sc_val = np.where((row_i.astype(np.int32) % 2) == 0, scale1, scale2)
    scale_ridge = np.clip(1.0 - np.abs(row_f - 0.85 * sc_val) * 3.2, 0.0, 1.0)
    h_bud = np.clip(0.35 + sc_val * 0.35 + (1.0 - row_f) * 0.30, 0.0, 1.0)
    # Warm chestnut scale base transitioning to lighter downy/pinkish swelling tip (v_b near 0)
    tip_t = np.clip(1.0 - v_b * 1.45, 0.0, 1.0)[..., None]
    c_bud_base = np.stack([128 + h_bud * 46, 86 + h_bud * 34, 68 + h_bud * 28], axis=-1)
    c_bud_tip = np.stack([224 + h_bud * 25, 196 + h_bud * 28, 192 + h_bud * 26], axis=-1)
    c_bud = c_bud_base * (1.0 - tip_t) + c_bud_tip * tip_t
    c_bud *= (1.0 - (1.0 - scale_ridge)[..., None] * 0.25)
    Image.fromarray(np.clip(c_bud, 0, 255).astype(np.uint8), "RGB").save(os.path.join(TEX_DIR, "bud_scale_albedo.png"))
    height_to_normal(h_bud, strength=4.2).save(os.path.join(TEX_DIR, "bud_scale_normal.png"))


# ---------------------------------------------------------------------------
# 3. Clean Binary GLTF 2.0 (.glb) Builder for Sculpted Pruning Tools & Pot
# ---------------------------------------------------------------------------
class MeshBuilder:
    def __init__(self):
        self.pos = []
        self.norm = []
        self.uv = []
        self.idx = []

    def add_triangle(self, a, b, c, uva=(0, 0), uvb=(1, 0), uvc=(0, 1)):
        va = np.array(a, dtype=np.float32)
        vb = np.array(b, dtype=np.float32)
        vc = np.array(c, dtype=np.float32)
        n = np.cross(vb - va, vc - va)
        nl = np.linalg.norm(n)
        if nl < 1e-8:
            return
        n /= nl
        base = len(self.pos)
        self.pos.extend([va.tolist(), vb.tolist(), vc.tolist()])
        self.norm.extend([n.tolist(), n.tolist(), n.tolist()])
        self.uv.extend([list(uva), list(uvb), list(uvc)])
        self.idx.extend([base, base + 1, base + 2])

    def add_quad(self, a, b, c, d, u0=0.0, v0=0.0, u1=1.0, v1=1.0):
        self.add_triangle(a, b, c, (u0, v0), (u1, v0), (u1, v1))
        self.add_triangle(a, c, d, (u0, v0), (u1, v1), (u0, v1))

    def add_tube(self, points, radii, segs=12, cap_start=True, cap_end=True):
        rings = []
        n_pts = len(points)
        prev_right = np.array([1.0, 0.0, 0.0], dtype=np.float32)
        for i, p in enumerate(points):
            p = np.array(p, dtype=np.float32)
            if i == 0:
                tang = np.array(points[1], dtype=np.float32) - p
            elif i == n_pts - 1:
                tang = p - np.array(points[i - 1], dtype=np.float32)
            else:
                tang = np.array(points[i + 1], dtype=np.float32) - np.array(points[i - 1], dtype=np.float32)
            tl = np.linalg.norm(tang)
            tang = tang / tl if tl > 1e-6 else np.array([0.0, 0.0, -1.0], dtype=np.float32)

            right = prev_right - tang * np.dot(prev_right, tang)
            if np.linalg.norm(right) < 1e-4:
                alt = np.array([0.0, 1.0, 0.0], dtype=np.float32)
                if abs(np.dot(alt, tang)) > 0.9:
                    alt = np.array([1.0, 0.0, 0.0], dtype=np.float32)
                right = np.cross(alt, tang)
            right /= np.linalg.norm(right)
            prev_right = right
            up = np.cross(tang, right)

            r = radii[i]
            rx, ry = (r[0], r[1]) if isinstance(r, tuple) else (r, r)
            ring = []
            for s in range(segs):
                a = 2.0 * math.pi * s / segs
                v = p + right * (math.cos(a) * rx) + up * (math.sin(a) * ry)
                ring.append(v)
            rings.append((ring, p, tang))

        for i in range(n_pts - 1):
            r0, _, _ = rings[i]
            r1, _, _ = rings[i + 1]
            v0_uv = i / max(1, n_pts - 1)
            v1_uv = (i + 1) / max(1, n_pts - 1)
            for s in range(segs):
                sn = (s + 1) % segs
                self.add_quad(r0[s], r0[sn], r1[sn], r1[s], s / segs, v0_uv, (s + 1) / segs, v1_uv)

        if cap_start:
            r0, p0, _ = rings[0]
            for s in range(segs):
                sn = (s + 1) % segs
                self.add_triangle(p0, r0[sn], r0[s])
        if cap_end:
            r1, p1, _ = rings[-1]
            for s in range(segs):
                sn = (s + 1) % segs
                self.add_triangle(p1, r1[s], r1[sn])

    def add_lathe(self, profile_rz, segs=24):
        rings = []
        for r, y in profile_rz:
            ring = []
            for s in range(segs):
                a = 2.0 * math.pi * s / segs
                ring.append((r * math.cos(a), y, r * math.sin(a)))
            rings.append((ring, y))
        for i in range(len(rings) - 1):
            r0, _ = rings[i]
            r1, _ = rings[i + 1]
            v0 = i / max(1, len(rings) - 1)
            v1 = (i + 1) / max(1, len(rings) - 1)
            for s in range(segs):
                sn = (s + 1) % segs
                self.add_quad(r0[s], r0[sn], r1[sn], r1[s], s / segs, v0, (s + 1) / segs, v1)


def export_glb(filepath: str, materials: list, nodes: list):
    bin_buf = bytearray()
    buffer_views = []
    accessors = []
    gltf_meshes = []
    gltf_nodes = []

    def append_bytes(data: bytes, target=None):
        while len(bin_buf) % 4 != 0:
            bin_buf.append(0)
        offset = len(bin_buf)
        bin_buf.extend(data)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            bv["target"] = target
        bv_idx = len(buffer_views)
        buffer_views.append(bv)
        return bv_idx

    for node in nodes:
        primitives = []
        for _, mat_idx, mb in node["parts"]:
            if not mb.idx:
                continue
            pos_arr = np.array(mb.pos, dtype=np.float32)
            norm_arr = np.array(mb.norm, dtype=np.float32)
            uv_arr = np.array(mb.uv, dtype=np.float32)
            idx_arr = np.array(mb.idx, dtype=np.uint32)

            bv_pos = append_bytes(pos_arr.tobytes(), 34962)
            bv_norm = append_bytes(norm_arr.tobytes(), 34962)
            bv_uv = append_bytes(uv_arr.tobytes(), 34962)
            bv_idx = append_bytes(idx_arr.tobytes(), 34963)

            acc_pos = len(accessors)
            accessors.append({
                "bufferView": bv_pos, "componentType": 5126, "count": len(pos_arr), "type": "VEC3",
                "min": pos_arr.min(axis=0).tolist(), "max": pos_arr.max(axis=0).tolist()
            })
            acc_norm = len(accessors)
            accessors.append({
                "bufferView": bv_norm, "componentType": 5126, "count": len(norm_arr), "type": "VEC3"
            })
            acc_uv = len(accessors)
            accessors.append({
                "bufferView": bv_uv, "componentType": 5126, "count": len(uv_arr), "type": "VEC2"
            })
            acc_idx = len(accessors)
            accessors.append({
                "bufferView": bv_idx, "componentType": 5125, "count": len(idx_arr), "type": "SCALAR"
            })
            primitives.append({
                "attributes": {"POSITION": acc_pos, "NORMAL": acc_norm, "TEXCOORD_0": acc_uv},
                "indices": acc_idx,
                "material": mat_idx
            })

        mesh_idx = len(gltf_meshes)
        gltf_meshes.append({"name": node["name"] + "_Mesh", "primitives": primitives})
        n_dict = {"name": node["name"], "mesh": mesh_idx}
        if "translation" in node:
            n_dict["translation"] = node["translation"]
        gltf_nodes.append(n_dict)

    gltf_mats = []
    for m in materials:
        gltf_mats.append({
            "name": m["name"],
            "pbrMetallicRoughness": {
                "baseColorFactor": m["color"],
                "metallicFactor": m["metallic"],
                "roughnessFactor": m["roughness"],
            },
            "doubleSided": m.get("doubleSided", False),
        })

    root_idx = len(gltf_nodes)
    gltf_nodes.append({"name": "Root", "children": list(range(root_idx))})

    while len(bin_buf) % 4 != 0:
        bin_buf.append(0)

    gltf = {
        "asset": {"version": "2.0", "generator": "VR Pruning AssetGen"},
        "scene": 0,
        "scenes": [{"nodes": [root_idx]}],
        "nodes": gltf_nodes,
        "meshes": gltf_meshes,
        "materials": gltf_mats,
        "buffers": [{"byteLength": len(bin_buf)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_buf)
    with open(filepath, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total_len))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(bin_buf), 0x004E4942))
        f.write(bin_buf)


def extrude_xz(mb: MeshBuilder, pts_xz: list, y_min: float, y_max: float):
    n = len(pts_xz)
    cx = sum(p[0] for p in pts_xz) / n
    cz = sum(p[1] for p in pts_xz) / n
    for i in range(n):
        p0 = pts_xz[i]
        p1 = pts_xz[(i + 1) % n]
        mb.add_triangle((cx, y_max, cz), (p1[0], y_max, p1[1]), (p0[0], y_max, p0[1]),
                        (0.5, 0.5), (p1[0] * 5 + 0.5, p1[1] * 5 + 0.5), (p0[0] * 5 + 0.5, p0[1] * 5 + 0.5))
        mb.add_triangle((cx, y_min, cz), (p0[0], y_min, p0[1]), (p1[0], y_min, p1[1]),
                        (0.5, 0.5), (p0[0] * 5 + 0.5, p0[1] * 5 + 0.5), (p1[0] * 5 + 0.5, p1[1] * 5 + 0.5))
        mb.add_quad(
            (p0[0], y_min, p0[1]), (p1[0], y_min, p1[1]),
            (p1[0], y_max, p1[1]), (p0[0], y_max, p0[1]),
            i / n, 0.0, (i + 1) / n, 1.0
        )


def build_secateurs_glb():
    mats = [
        {"name": "Steel", "color": [0.80, 0.83, 0.86, 1.0], "metallic": 0.92, "roughness": 0.24},
        {"name": "GripRed", "color": [0.76, 0.16, 0.12, 1.0], "metallic": 0.04, "roughness": 0.68},
        {"name": "RubberDark", "color": [0.14, 0.14, 0.15, 1.0], "metallic": 0.05, "roughness": 0.78},
        {"name": "Brass", "color": [0.85, 0.66, 0.24, 1.0], "metallic": 0.95, "roughness": 0.28},
    ]
    lower_steel = MeshBuilder()
    hook_pts = [
        (-0.008, 0.020), (-0.015, 0.002), (-0.018, -0.025),
        (-0.012, -0.052), (-0.001, -0.068), (0.010, -0.064),
        (0.004, -0.048), (-0.003, -0.026), (0.004, -0.004), (0.008, 0.018)
    ]
    extrude_xz(lower_steel, hook_pts, -0.0038, 0.0)

    brass = MeshBuilder()
    brass.add_tube([(0, -0.006, 0), (0, 0.006, 0)], [0.0065, 0.0065], segs=14)

    lower_grip = MeshBuilder()
    l_pts = [(0.002, -0.002, 0.015), (0.012, -0.002, 0.045), (0.022, -0.002, 0.085),
             (0.026, -0.002, 0.125), (0.020, -0.002, 0.155)]
    lower_grip.add_tube(l_pts, [(0.007, 0.008), (0.009, 0.010), (0.010, 0.011), (0.0095, 0.0105), (0.0075, 0.0085)], segs=12)

    upper_steel = MeshBuilder()
    blade_pts = [
        (-0.007, 0.020), (-0.009, 0.00), (0.002, -0.022),
        (0.014, -0.044), (0.008, -0.068), (-0.004, -0.062),
        (-0.004, -0.036), (0.002, -0.014), (0.007, 0.018)
    ]
    extrude_xz(upper_steel, blade_pts, 0.0002, 0.0034)

    upper_grip = MeshBuilder()
    u_pts = [(-0.002, 0.002, 0.015), (-0.014, 0.002, 0.045), (-0.025, 0.002, 0.085),
             (-0.029, 0.002, 0.125), (-0.022, 0.002, 0.155)]
    upper_grip.add_tube(u_pts, [(0.007, 0.008), (0.009, 0.010), (0.0105, 0.0115), (0.010, 0.011), (0.0075, 0.0085)], segs=12)

    rubber_bumper = MeshBuilder()
    rubber_bumper.add_tube([(0.012, 0, 0.065), (-0.012, 0, 0.065)], [0.0035, 0.0035], segs=8)

    export_glb(os.path.join(MOD_DIR, "secateurs.glb"), mats, [
        {"name": "BodyGroup", "translation": [0.0, 0.0, -0.06], "parts": [
            ("LowerHook", 0, lower_steel),
            ("PivotBolt", 3, brass),
            ("LowerGrip", 1, lower_grip),
            ("Spring", 2, rubber_bumper),
        ]},
        {"name": "BladePivot", "translation": [0.0, 0.0, -0.06], "parts": [
            ("UpperBlade", 0, upper_steel),
            ("UpperGrip", 1, upper_grip),
        ]},
    ])


def build_loppers_glb():
    mats = [
        {"name": "Steel", "color": [0.78, 0.81, 0.85, 1.0], "metallic": 0.92, "roughness": 0.25},
        {"name": "AnodizedAlum", "color": [0.22, 0.44, 0.28, 1.0], "metallic": 0.72, "roughness": 0.36},
        {"name": "RubberGrip", "color": [0.15, 0.15, 0.16, 1.0], "metallic": 0.04, "roughness": 0.82},
        {"name": "Brass", "color": [0.82, 0.62, 0.22, 1.0], "metallic": 0.94, "roughness": 0.30},
    ]
    lower_steel = MeshBuilder()
    hook_pts = [
        (-0.012, 0.025), (-0.024, -0.005), (-0.028, -0.042),
        (-0.015, -0.080), (0.004, -0.095), (0.022, -0.086),
        (0.010, -0.064), (-0.005, -0.038), (0.005, -0.005), (0.012, 0.022)
    ]
    extrude_xz(lower_steel, hook_pts, -0.005, 0.0)

    lower_arm = MeshBuilder()
    lower_arm.add_tube([(0.006, -0.003, 0.015), (0.028, -0.003, 0.16), (0.045, -0.003, 0.32)], [0.009, 0.009, 0.009], segs=12)
    lower_grip = MeshBuilder()
    lower_grip.add_tube([(0.045, -0.003, 0.31), (0.056, -0.003, 0.45), (0.060, -0.003, 0.50)], [0.0125, 0.013, 0.011], segs=12)

    brass = MeshBuilder()
    brass.add_tube([(0, -0.009, 0), (0, 0.009, 0)], [0.009, 0.009], segs=14)

    upper_steel = MeshBuilder()
    blade_pts = [
        (-0.010, 0.025), (-0.014, 0.0), (0.004, -0.032),
        (0.024, -0.062), (0.012, -0.092), (-0.008, -0.082),
        (-0.008, -0.048), (0.002, -0.016), (0.010, 0.022)
    ]
    extrude_xz(upper_steel, blade_pts, 0.0003, 0.0052)

    upper_arm = MeshBuilder()
    upper_arm.add_tube([(-0.006, 0.003, 0.015), (-0.028, 0.003, 0.16), (-0.045, 0.003, 0.32)], [0.009, 0.009, 0.009], segs=12)
    upper_grip = MeshBuilder()
    upper_grip.add_tube([(-0.045, 0.003, 0.31), (-0.056, 0.003, 0.45), (-0.060, 0.003, 0.50)], [0.0125, 0.013, 0.011], segs=12)

    export_glb(os.path.join(MOD_DIR, "loppers.glb"), mats, [
        {"name": "BodyGroup", "translation": [0.0, 0.0, -0.34], "parts": [
            ("LowerHook", 0, lower_steel),
            ("LowerArm", 1, lower_arm),
            ("LowerGrip", 2, lower_grip),
            ("PivotBolt", 3, brass),
        ]},
        {"name": "BladePivot", "translation": [0.0, 0.0, -0.34], "parts": [
            ("UpperBlade", 0, upper_steel),
            ("UpperArm", 1, upper_arm),
            ("UpperGrip", 2, upper_grip),
        ]},
    ])


def build_pruning_saw_glb():
    mats = [
        {"name": "SawSteel", "color": [0.76, 0.79, 0.83, 1.0], "metallic": 0.94, "roughness": 0.22},
        {"name": "WalnutHandle", "color": [0.42, 0.23, 0.12, 1.0], "metallic": 0.02, "roughness": 0.62},
        {"name": "RubberInlay", "color": [0.16, 0.16, 0.17, 1.0], "metallic": 0.04, "roughness": 0.85},
        {"name": "Brass", "color": [0.84, 0.65, 0.25, 1.0], "metallic": 0.92, "roughness": 0.30},
    ]
    blade = MeshBuilder()
    top_spine = []
    bot_teeth = []
    n_teeth = 26
    for i in range(n_teeth + 1):
        t = i / n_teeth
        z = -0.02 - t * 0.28
        curve_y = -0.018 * (t * t)
        width = 0.032 * (1.0 - 0.55 * t)
        top_spine.append((curve_y + width * 0.5, z))
        bot_teeth.append((curve_y - width * 0.5, z))
        if i < n_teeth:
            zt = z - (0.28 / n_teeth) * 0.52
            yt = curve_y - width * 0.5 - 0.0045
            bot_teeth.append((yt, zt))

    poly_yz = top_spine + list(reversed(bot_teeth))
    n = len(poly_yz)
    cx = sum(p[0] for p in poly_yz) / n
    cz = sum(p[1] for p in poly_yz) / n
    x0, x1 = -0.0011, 0.0011
    for i in range(n):
        p0 = poly_yz[i]
        p1 = poly_yz[(i + 1) % n]
        blade.add_triangle((x1, cx, cz), (x1, p0[0], p0[1]), (x1, p1[0], p1[1]))
        blade.add_triangle((x0, cx, cz), (x0, p1[0], p1[1]), (x0, p0[0], p0[1]))
        blade.add_quad((x0, p0[0], p0[1]), (x1, p0[0], p0[1]), (x1, p1[0], p1[1]), (x0, p1[0], p1[1]))

    handle = MeshBuilder()
    h_pts = [(0, 0.0, -0.025), (0, -0.004, 0.02), (0, -0.014, 0.07), (0, -0.030, 0.125), (0, -0.044, 0.16)]
    handle.add_tube(h_pts, [(0.011, 0.015), (0.013, 0.018), (0.014, 0.019), (0.0135, 0.018), (0.011, 0.015)], segs=14)

    bolster = MeshBuilder()
    bolster.add_tube([(0, 0, -0.030), (0, 0, -0.008)], [(0.012, 0.017), (0.012, 0.017)], segs=14)

    export_glb(os.path.join(MOD_DIR, "pruning_saw.glb"), mats, [
        {"name": "SawBody", "parts": [
            ("Blade", 0, blade),
            ("Handle", 1, handle),
            ("Bolster", 3, bolster),
        ]}
    ])


def build_planter_pot_glb():
    mats = [
        {"name": "Terracotta", "color": [0.68, 0.34, 0.21, 1.0], "metallic": 0.02, "roughness": 0.78},
        {"name": "SoilMulch", "color": [0.19, 0.14, 0.10, 1.0], "metallic": 0.0, "roughness": 0.96},
    ]
    pot = MeshBuilder()
    pot.add_lathe([
        (0.001, 0.0), (0.19, 0.0), (0.20, 0.03), (0.21, 0.05),
        (0.25, 0.22), (0.275, 0.34), (0.295, 0.35), (0.300, 0.39),
        (0.288, 0.40), (0.265, 0.39), (0.255, 0.33), (0.001, 0.32)
    ], segs=32)

    soil = MeshBuilder()
    soil.add_lathe([
        (0.256, 0.335), (0.19, 0.355), (0.11, 0.372), (0.001, 0.382)
    ], segs=28)

    export_glb(os.path.join(MOD_DIR, "planter_pot.glb"), mats, [
        {"name": "PlanterGroup", "parts": [
            ("PotBody", 0, pot),
            ("SoilMound", 1, soil),
        ]}
    ])


# ---------------------------------------------------------------------------
# 4. Realistic Procedural Spatial Audio WAVs
# ---------------------------------------------------------------------------
def write_wav(filename: str, samples: np.ndarray, sr: int = 44100):
    pcm = np.clip(samples * 32767.0, -32767, 32767).astype(np.int16)
    with wave.open(os.path.join(AUD_DIR, filename), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def generate_audio():
    sr = 44100
    rng = np.random.default_rng(88)

    t = np.linspace(0, 0.16, int(sr * 0.16), dtype=np.float32)
    env = np.exp(-t * 36.0)
    snap = np.sin(2 * np.pi * (1450 * np.exp(-t * 25) + 420) * t) * 0.45
    blade_ring = np.sin(2 * np.pi * 3650 * t) * np.exp(-t * 55.0) * 0.25
    fiber = rng.normal(0, 1, len(t)).astype(np.float32) * np.exp(-t * 48.0) * 0.38
    write_wav("snip_clean.wav", (snap + blade_ring + fiber) * env * 0.9)

    t2 = np.linspace(0, 0.26, int(sr * 0.26), dtype=np.float32)
    thump = np.sin(2 * np.pi * (240 * np.exp(-t2 * 16) + 95) * t2) * np.exp(-t2 * 14.0) * 0.55
    crunch = rng.normal(0, 1, len(t2)).astype(np.float32) * (np.exp(-t2 * 22.0) + 0.4 * np.exp(-((t2 - 0.04) / 0.02) ** 2)) * 0.45
    write_wav("snip_thick.wav", (thump + crunch) * 0.9)

    t3 = np.linspace(0, 0.14, int(sr * 0.14), dtype=np.float32)
    clack = (np.sin(2 * np.pi * 620 * t3) + 0.6 * np.sin(2 * np.pi * 1120 * t3)) * np.exp(-t3 * 42.0)
    write_wav("snip_jam.wav", clack * 0.65)

    t4 = np.linspace(0, 0.22, int(sr * 0.22), dtype=np.float32)
    teeth_mod = 0.5 + 0.5 * np.sin(2 * np.pi * 92 * t4)
    rasp = rng.normal(0, 1, len(t4)).astype(np.float32) * teeth_mod * np.sin(np.pi * t4 / 0.22)
    wood_res = np.sin(2 * np.pi * 320 * t4) * 0.15 * np.sin(np.pi * t4 / 0.22)
    write_wav("saw_stroke.wav", (rasp * 0.55 + wood_res) * 0.85)

    t5 = np.linspace(0, 0.42, int(sr * 0.42), dtype=np.float32)
    crack1 = rng.normal(0, 1, len(t5)).astype(np.float32) * np.exp(-t5 * 14.0) * 0.65
    crack2 = np.sin(2 * np.pi * (380 * np.exp(-t5 * 12) + 110) * t5) * np.exp(-t5 * 10.0) * 0.55
    pop = rng.normal(0, 1, len(t5)).astype(np.float32) * np.exp(-((t5 - 0.09) / 0.015) ** 2) * 0.50
    write_wav("branch_crack.wav", np.tanh(crack1 + crack2 + pop) * 0.85)

    t6 = np.linspace(0, 0.35, int(sr * 0.35), dtype=np.float32)
    rustle = rng.normal(0, 1, len(t6)).astype(np.float32)
    rustle = np.convolve(rustle, [0.3, -0.5, 0.3], mode="same")
    env6 = np.maximum(0.0, np.sin(np.pi * t6 / 0.35)) ** 1.4
    write_wav("leaves_rustle.wav", rustle * env6 * 0.55)

    t7 = np.linspace(0, 0.05, int(sr * 0.05), dtype=np.float32)
    uic = np.sin(2 * np.pi * 980 * t7) * np.exp(-t7 * 95.0) * 0.45
    write_wav("ui_click.wav", uic)


if __name__ == "__main__":
    print("Generating sharp botanical bark & cut-wood PBR textures...")
    generate_bark("bark_apple", (42, 33, 25), (84, 65, 49), (124, 102, 82), (108, 124, 82), 1.4, 0.62, 0.45, 11)
    generate_bark("bark_maple", (56, 54, 46), (98, 94, 82), (138, 132, 116), (86, 118, 70), 0.75, 0.22, 0.85, 29)
    generate_bark("bark_olive", (62, 58, 52), (110, 104, 94), (154, 148, 134), (122, 134, 96), 1.65, 0.78, 0.15, 61)
    generate_bark("bark_dead", (44, 42, 40), (88, 86, 82), (142, 140, 134), (160, 168, 142), 1.6, 0.82, 0.0, 47)
    generate_wood_cut("wood_cut", dead=False)
    generate_wood_cut("wood_cut_dead", dead=True)

    print("Generating shaded botanical foliage cluster sprites...")
    generate_foliage_cluster("leaf_apple_albedo.png", "apple")
    generate_foliage_cluster("leaf_maple_albedo.png", "maple")
    generate_foliage_cluster("leaf_olive_albedo.png", "olive")
    generate_foliage_cluster("leaf_dead_albedo.png", "dead")

    print("Generating terracotta, soil, tool textures & icon...")
    generate_misc_textures()

    print("Building 3D GLB models...")
    build_secateurs_glb()
    build_loppers_glb()
    build_pruning_saw_glb()
    build_planter_pot_glb()

    print("Synthesizing spatial audio WAVs...")
    generate_audio()
    print("All assets generated successfully!")
