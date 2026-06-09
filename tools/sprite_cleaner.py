import cv2
import numpy as np
import argparse
import sys
import os

def cv2_imread(file_path):
    return cv2.imdecode(np.fromfile(file_path, dtype=np.uint8), cv2.IMREAD_UNCHANGED)

def cv2_imwrite(file_path, img):
    cv2.imencode('.png', img)[1].tofile(file_path)

def clean_sprite(img, tolerance=20):
    """
    高级去背景算法：
    1. 使用 FloodFill 从角落识别外部背景（保护内部像素）
    2. 识别内部闭环背景块，并根据大小进行过滤（防止误杀细小像素）
    3. 使用软阈值处理边缘，防止锯齿和像素丢失
    """
    if img is None:
        return None
        
    # 如果已经是 BGRA，取前 3 通道处理
    if len(img.shape) == 3 and img.shape[2] == 4:
        bgr = img[:, :, :3].copy()
    else:
        bgr = img.copy()
        
    h, w = bgr.shape[:2]
    
    # 1. 采样背景色 (四个角落的平均值)
    corners = [bgr[0,0], bgr[0,w-1], bgr[h-1,0], bgr[h-1,w-1]]
    bg_color_bgr = np.mean(corners, axis=0)
    bg_color_list = [int(c) for c in bg_color_bgr]
    
    # 转换为HSV判断背景类型
    bg_hsv_pixel = cv2.cvtColor(np.uint8([[bg_color_bgr]]), cv2.COLOR_BGR2HSV)[0][0]
    bg_h = bg_hsv_pixel[0]
    bg_s = bg_hsv_pixel[1]
    bg_v = bg_hsv_pixel[2]
    
    is_purple = (130 <= bg_h <= 170) or (bg_color_list[0] > 150 and bg_color_list[2] > 150 and bg_color_list[1] < 150)
    is_green = (35 <= bg_h <= 90)
    is_red = (bg_h <= 10 or bg_h >= 170) and bg_s > 50 # 红色背景判断
    
    # 2. 识别所有“看起来像背景”的像素 (全图蒙版)
    dist = np.sqrt(np.sum((bgr.astype(np.float32) - bg_color_bgr)**2, axis=2))
    
    # 3. FloodFill 识别外部连通背景
    ff_mask = np.zeros((h + 2, w + 2), np.uint8)
    for start_point in [(0,0), (w-1,0), (0,h-1), (w-1,h-1), (w//2, 0), (w//2, h-1), (0, h//2), (w-1, h//2)]:
        if dist[start_point[1], start_point[0]] < tolerance * 2.0:
            cv2.floodFill(bgr, ff_mask, start_point, 0, 
                          (tolerance, tolerance, tolerance), 
                          (tolerance, tolerance, tolerance), 
                          4 | cv2.FLOODFILL_MASK_ONLY | (255 << 8))
    outer_bg_mask = ff_mask[1:-1, 1:-1]
    
    # 4. 识别并过滤内部闭环背景块
    # 显著提高内部块判定的阈值。如果是红色/绿色等纯色背景，内部同色块极有可能是主体的一部分
    internal_bg_mask = np.zeros((h, w), np.uint8)
    if not (is_red or is_green or is_purple): # 只有在非标准纯色背景下才尝试自动清理大块内部背景
        potential_internal = ((dist < tolerance * 1.2) & (outer_bg_mask == 0)).astype(np.uint8) * 255
        num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(potential_internal, connectivity=8)
        for i in range(1, num_labels):
            area = stats[i, cv2.CC_STAT_AREA]
            # 只有非常大的内部块才被认为是背景空洞（例如手臂间的空隙）
            if area > 500: 
                internal_bg_mask[labels == i] = 255
            
    final_bg_mask = cv2.bitwise_or(outer_bg_mask, internal_bg_mask)
    
    # 5. 生成软阈值 Alpha
    alpha = np.ones((h, w), dtype=np.uint8) * 255
    alpha[final_bg_mask > 0] = 0
    
    # 只有在外部连通区域附近才进行边缘软化，防止主体内部颜色相近区域变透明
    edge_soften_mask = cv2.dilate(outer_bg_mask, np.ones((5,5), np.uint8))
    edge_alpha = np.clip((dist - tolerance*0.5) / (tolerance), 0, 1) * 255
    
    # 主体内部像素（非 edge_soften_mask 覆盖区域）强制不透明
    safe_alpha = np.where(edge_soften_mask > 0, edge_alpha.astype(np.uint8), 255)
    alpha = np.minimum(alpha, safe_alpha)

    # 6. 溢出处理 (Despill)
    b = bgr[:, :, 0].astype(np.float32)
    g = bgr[:, :, 1].astype(np.float32)
    r = bgr[:, :, 2].astype(np.float32)
    
    if is_purple:
        r_new = np.where((r > g) & (b > g), np.minimum(r, g * 1.2), r)
        b_new = np.where((r > g) & (b > g), np.minimum(b, g * 1.2), b)
        bgr[:, :, 2] = r_new.astype(np.uint8)
        bgr[:, :, 0] = b_new.astype(np.uint8)
    elif is_green:
        max_rb = np.maximum(r, b)
        g_new = np.where(g > max_rb * 1.1, max_rb * 1.1, g)
        bgr[:, :, 1] = g_new.astype(np.uint8)
    elif is_red:
        max_gb = np.maximum(g, b)
        r_new = np.where(r > max_gb * 1.2, max_gb * 1.2, r)
        bgr[:, :, 2] = r_new.astype(np.uint8)

    # 7. 解决 Godot 像素丢失/边缘发黑的问题 (Alpha Bleeding)
    if np.sum(alpha < 255) > 0:
        bgr_filled = bgr.copy()
        for _ in range(3):
            dilated = cv2.dilate(bgr_filled, np.ones((3,3), np.uint8))
            bgr_filled = np.where(alpha[:, :, np.newaxis] == 0, dilated, bgr_filled)
        bgr = bgr_filled

    bgra = cv2.cvtColor(bgr, cv2.COLOR_BGR2BGRA)
    bgra[:, :, 3] = alpha
    return bgra

def main():
    parser = argparse.ArgumentParser(description="Sprite Cleaner")
    parser.add_argument("input", help="输入图片的路径")
    parser.add_argument("output", help="输出图片的路径")
    parser.add_argument("--tolerance", type=int, default=20, help="去背景容差")
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"错误: 找不到文件 {args.input}")
        sys.exit(1)

    img = cv2_imread(args.input)
    if img is None:
        sys.exit(1)
        
    cleaned = clean_sprite(img, args.tolerance)
    cv2_imwrite(args.output, cleaned)
    print(f"成功! 处理后的素材已保存至: {args.output}")

if __name__ == '__main__':
    main()
