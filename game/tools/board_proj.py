# Карта-гекс «полюс в центре» (как эмблема ООН): общие формулы для инструментов.
# Те же формулы в board.gd (игра) и в terrain_shaders.gd (шейдер). Менять только вместе.
#
# S: прежняя развёртка 36000 x 18000 м (x долгота, 0 м = -180, 18000 м = 0; y от Северного полюса
#    к Южному). Все исходные данные (карта высот, климат, регионы, атмосфера) лежат в ней.
# P: доска-гекс 41625 x 36000 м. Шестиугольник плоской стороной вверх, центр CENTER = Северный полюс,
#    Южный полюс = край гекса. Расстояние от полюса по меридиану как на шаре (равнопромежуточно),
#    в северной половине широты это круги, к югу они плавно переходят в шестиугольник края.
#    Меридиан 0 (середина старой карты) смотрит вниз, восток против часовой стрелки.
import numpy as np, math

SRC_W, SRC_H = 36000.0, 18000.0
BOARD_W, BOARD_H = 41625.0, 36000.0
CX, CY = BOARD_W * 0.5, BOARD_H * 0.5
APO = 18000.0                       # центр -> середина стороны гекса (Северный полюс -> Южный)
RAS_NX, RAS_NY = 4736, 4096         # растры доски, клетка 8,7890625 м (как у прежних 4096 x 2048)
RAS_M = BOARD_H / RAS_NY
C30 = math.sqrt(3.0) * 0.5


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def dsmooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return 6.0 * t * (1.0 - t) / (b - a)


def hex_c(ux, uy):
    """«Шестиугольная длина» единичного направления: 1 к середине стороны, 0,866 к углу."""
    return np.maximum(np.abs(uy), np.maximum(np.abs(C30 * ux + 0.5 * uy), np.abs(-C30 * ux + 0.5 * uy)))


def hex_norm(vx, vy):
    return np.maximum(np.abs(vy), np.maximum(np.abs(C30 * vx + 0.5 * vy), np.abs(-C30 * vx + 0.5 * vy)))


def to_board(sx, sy):
    """S -> P"""
    t = np.clip(np.asarray(sy, np.float64) / SRC_H, 0.0, 1.0)
    lam = (np.asarray(sx, np.float64) - SRC_W * 0.5) / SRC_W * 2.0 * math.pi
    ux = np.sin(lam); uy = np.cos(lam)
    c = hex_c(ux, uy)
    w = smooth(0.5, 1.0, t)
    rho = APO * t / (1.0 - w * (1.0 - c))
    return CX + rho * ux, CY + rho * uy


def to_src(px, py):
    """P -> S. Возвращает (sx, sy, t, inside); t = доля пути от Северного полюса к Южному."""
    vx = np.asarray(px, np.float64) - CX; vy = np.asarray(py, np.float64) - CY
    rho = np.hypot(vx, vy)
    safe = np.maximum(rho, 1e-9)
    ux = np.where(rho > 1e-9, vx / safe, 0.0); uy = np.where(rho > 1e-9, vy / safe, 1.0)
    lam = np.arctan2(ux, uy)
    sx = np.mod(SRC_W * 0.5 + lam / (2.0 * math.pi) * SRC_W, SRC_W)
    c = hex_c(ux, uy)
    t = rho / APO
    for _ in range(6):
        f = APO * t - rho * (1.0 - smooth(0.5, 1.0, t) * (1.0 - c))
        fp = APO + rho * (1.0 - c) * dsmooth(0.5, 1.0, t)
        t = np.clip(t - f / fp, 0.0, 1.5)
    inside = hex_norm(vx, vy) <= APO
    return sx, np.clip(t, 0.0, 1.0) * SRC_H, t, inside


def axes(px, py):
    """Местные оси в точке доски: (восток ex, ey), (юг sx, sy)."""
    vx = np.asarray(px, np.float64) - CX; vy = np.asarray(py, np.float64) - CY
    rho = np.maximum(np.hypot(vx, vy), 1e-9)
    ux = vx / rho; uy = vy / rho
    return (uy, -ux), (ux, uy)


if __name__ == '__main__':
    rng = np.random.default_rng(1)
    sx = rng.uniform(0, SRC_W, 200000); sy = rng.uniform(0, SRC_H, 200000)
    px, py = to_board(sx, sy)
    bx, by, t, ins = to_src(px, py)
    dx = np.abs(np.mod(bx - sx + SRC_W / 2, SRC_W) - SRC_W / 2)
    m = sy > 5.0
    print('обратный перевод: макс. ошибка x %.4f м (без полюса), y %.4f м; всё внутри гекса: %s' % (dx[m].max(), np.abs(by - sy).max(), ins.all()))
    ex, ey = to_board(np.linspace(0, SRC_W, 13), np.full(13, SRC_H))
    print('Южный полюс по краю гекса: hex_norm =', np.round(hex_norm(ex - CX, ey - CY), 3))
