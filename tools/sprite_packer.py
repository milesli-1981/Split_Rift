import cv2
import numpy as np
import argparse
import sys
import os
import glob
from watermark_remover import remove_watermark

def cv2_imread(file_path):
    return cv2.imdecode(np.fromfile(file_path, dtype=np.uint8), cv2.IMREAD_UNCHANGED)

def cv2_imwrite(file_path, img):
    # 使用 32bit RGBA 导出，并设置压缩等级为 1-3（无损，不丢像素）
    # IMWRITE_PNG_COMPRESSION 默认是 3，范围 0-9
    cv2.imencode('.png', img, [cv2.IMWRITE_PNG_COMPRESSION, 3])[1].tofile(file_path)

def repair_source_channels(img):
    """
    独立功能：修复源文件通道损坏问题
    专门针对源文件 Alpha 通道内部（非边缘）丢失像素的情况。
    逻辑：识别出所有被不透明区域包围的透明空洞，并将其强制填补为不透明。
    """
    if img is None:
        return None
    
    # 如果源文件没有 Alpha 通道，直接返回
    if img.shape[2] != 4:
        return img

    bgr = img[:, :, :3]
    alpha = img[:, :, 3]
    
    # 1. 提取原始 Alpha 掩码 (0 为透明，255 为不透明)
    # 我们认为 Alpha > 10 的都是角色主体
    _, mask = cv2.threshold(alpha, 10, 255, cv2.THRESH_BINARY)
    
    # 2. 填充内部空洞
    # 算法：从角落进行 FloodFill，剩下的未填充区域即为“主体+内部空洞”
    h, w = mask.shape
    filled_mask = mask.copy()
    ff_mask = np.zeros((h + 2, w + 2), np.uint8)
    
    # 从四个角开始填充背景
    for pt in [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]:
        if filled_mask[pt[1], pt[0]] == 0:
            cv2.floodFill(filled_mask, ff_mask, pt, 255)
    
    # 此时 filled_mask 中，原本是 0 的内部空洞依然是 0，而外部背景变成了 255
    # 我们通过反转找到这些真正的内部空洞
    internal_holes = cv2.bitwise_not(filled_mask)
    
    # 3. 修复 Alpha：将所有内部空洞设为不透明 (255)
    repaired_alpha = alpha.copy()
    repaired_alpha[internal_holes > 0] = 255
    
    # 合成回修复后的 RGBA
    return cv2.merge([bgr[:,:,0], bgr[:,:,1], bgr[:,:,2], repaired_alpha])

def clean_sprite(img, tolerance=20, despill_strength=1.0):
    """
    更强大的去背景算法 (LAB 空间 + 边缘去色)：
    1. 使用 LAB 颜色空间计算 Delta E 距离，比 BGR 空间更符合视觉感官。
    2. 多点种子 FloodFill 锁定外部背景。
    3. 引入 Despill (去色) 逻辑，消除边缘残留的背景色（如绿边）。
    """
    if img is None:
        return None
        
    if len(img.shape) == 3 and img.shape[2] == 4:
        bgr = img[:, :, :3].copy()
    else:
        bgr = img.copy()
        
    h, w = bgr.shape[:2]
    
    # 1. 转换到 LAB 颜色空间
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    
    # 2. 采样背景色 (LAB 空间)
    # 获取四边的像素
    edges = [lab[0, :], lab[h-1, :], lab[:, 0], lab[:, w-1]]
    edge_pixels_lab = np.concatenate([e.reshape(-1, 3) for e in edges])
    
    # 使用中位数作为初始参考
    bg_color_lab = np.median(edge_pixels_lab, axis=0).astype(np.float32)
    
    # 优化背景色采样：剔除距离中位数太远的像素（可能是角色触碰到边缘）
    dists_to_median = np.sqrt(np.sum((edge_pixels_lab - bg_color_lab)**2, axis=1))
    valid_bg_mask = dists_to_median < tolerance * 1.5
    if np.any(valid_bg_mask):
        bg_color_lab = np.mean(edge_pixels_lab[valid_bg_mask], axis=0).astype(np.float32)
    
    # 计算全图到背景色的距离 (Delta E 简化版)
    dist = np.sqrt(np.sum((lab.astype(np.float32) - bg_color_lab)**2, axis=2))
    
    # 3. FloodFill 识别外部连通背景
    # 针对蓝色背景可能存在的 JPG 伪影或噪点，对用于检测的 LAB 图进行轻微平滑
    lab_smooth = cv2.GaussianBlur(lab, (3, 3), 0)
    
    ff_mask = np.zeros((h + 2, w + 2), np.uint8)
    flags = 4 | cv2.FLOODFILL_MASK_ONLY | cv2.FLOODFILL_FIXED_RANGE | (255 << 8)
    
    seed_points = []
    # 采样步长减小，增加覆盖面
    step = 10
    for x in range(0, w, step):
        seed_points.append((x, 0))
        seed_points.append((x, h - 1))
    for y in range(0, h, step):
        seed_points.append((0, y))
        seed_points.append((w - 1, y))
    
    for start_point in seed_points:
        # 严谨的种子点检查：必须非常接近背景色才作为种子
        if dist[start_point[1], start_point[0]] < tolerance * 1.0:
            # 在平滑后的图上进行漫水填充，提高对噪点的鲁棒性
            cv2.floodFill(lab_smooth, ff_mask, start_point, 0, 
                          (tolerance, tolerance, tolerance), 
                          (tolerance, tolerance, tolerance), 
                          flags)
    
    outer_bg_mask = ff_mask[1:-1, 1:-1]
    
    # 4. 生成 Alpha
    kernel = np.ones((3, 3), np.uint8)
    dilated_bg = cv2.dilate(outer_bg_mask, kernel, iterations=2)
    
    alpha = np.ones((h, w), dtype=np.uint8) * 255
    soft_edge = np.clip((dist - tolerance * 0.4) / (tolerance * 0.8), 0, 1) * 255
    
    alpha = np.where(dilated_bg > 0, 
                     np.where(outer_bg_mask > 0, 0, soft_edge.astype(np.uint8)), 
                     255)

    # 5. Despill (边缘去色)
    if despill_strength > 0:
        # 识别背景色相（基于 LAB 的 a/b 分量）
        # a < 128 为绿/青，b < 128 为蓝
        if bg_color_lab[1] < 115: # 绿色背景倾向
            r, g, b = bgr[:,:,2], bgr[:,:,1], bgr[:,:,0]
            avg_rb = (r.astype(np.float16) + b.astype(np.float16)) / 2
            # 只有当像素确实偏绿，且在边缘区域时才去色
            mask_despill = (dilated_bg > 0) & (alpha > 0) & (g > r) & (g > b)
            
            if np.any(mask_despill):
                target_g = np.minimum(g[mask_despill], avg_rb[mask_despill]).astype(np.uint8)
                g[mask_despill] = (g[mask_despill] * (1.0 - despill_strength) + 
                                   target_g * despill_strength).astype(np.uint8)
                bgr[:,:,1] = g
        elif bg_color_lab[2] < 115: # 蓝色背景倾向
            r, g, b = bgr[:,:,2], bgr[:,:,1], bgr[:,:,0]
            avg_rg = (r.astype(np.float16) + g.astype(np.float16)) / 2
            # 只有当像素确实偏蓝，且在边缘区域时才去色
            mask_despill = (dilated_bg > 0) & (alpha > 0) & (b > r) & (b > g)
            
            if np.any(mask_despill):
                target_b = np.minimum(b[mask_despill], avg_rg[mask_despill]).astype(np.uint8)
                b[mask_despill] = (b[mask_despill] * (1.0 - despill_strength) + 
                                   target_b * despill_strength).astype(np.uint8)
                bgr[:,:,0] = b

    # 清除完全透明区域的 RGB
    bgr[alpha == 0] = [0, 0, 0]

    # 合成 BGRA
    bgra = cv2.merge([bgr[:,:,0], bgr[:,:,1], bgr[:,:,2], alpha])
    return bgra

def main():
    parser = argparse.ArgumentParser(description="Sprite Packer & Cleaner")
    parser.add_argument("input_dir", help="包含原始序列图的文件夹路径")
    parser.add_argument("output_file", help="输出拼接后 SpriteSheet 的路径")
    parser.add_argument("--cols", type=int, default=4, help="每行最大图片数 (默认4)")
    parser.add_argument("--tolerance", type=int, default=20, help="去背景容差 (调低以保护像素)")
    parser.add_argument("--despill", type=float, default=0.8, help="去色强度 (0.0-1.0, 默认0.8)")
    parser.add_argument("--max_size", type=int, default=1024, help="输出图片的最大尺寸 (默认1024)")
    parser.add_argument("--remove_watermark", action="store_true", help="是否启用去水印功能")
    parser.add_argument("--watermark_rects", help="水印矩形区域 (x,y,w,h;...)")
    parser.add_argument("--v_thresh", type=int, default=180, help="去水印亮度阈值 (0-255)")
    args = parser.parse_args()

    if not os.path.isdir(args.input_dir):
        print(f"错误: 找不到目录 {args.input_dir}")
        sys.exit(1)

    # 获取所有图片文件
    extensions = ['*.png', '*.jpg', '*.jpeg', '*.bmp', '*.webp']
    image_files = []
    for ext in extensions:
        image_files.extend(glob.glob(os.path.join(args.input_dir, ext)))
    
    # 按文件名排序确保序列正确
    image_files.sort()

    if not image_files:
        print(f"在目录中没有找到图片文件: {args.input_dir}")
        sys.exit(1)

    processed_images = []
    max_w = 0
    max_h = 0

    print(f"开始处理目录 {args.input_dir} 中的 {len(image_files)} 张图片...")

    for f in image_files:
        print(f"  正在处理: {os.path.basename(f)}")
        img_raw = cv2_imread(f)
        
        # --- 第一步：独立功能 - 修复源文件通道损坏 ---
        # 专门填补 Alpha 通道中可能存在的内部空洞
        img_repaired = repair_source_channels(img_raw)
        
        # --- 第二步：通道规范化 ---
        # 强制将图像转换为纯 BGR (3通道)，确保去底是基于真实的 RGB 数据
        # 即使 Alpha 被修复了，我们也重新生成它以确保最干净的效果
        if img_repaired.shape[2] == 4:
            img = cv2.cvtColor(img_repaired, cv2.COLOR_BGRA2BGR)
        else:
            img = img_repaired.copy()
        
        # 1. 可选的去水印处理
        if args.remove_watermark:
            kwargs = {"v_thresh": args.v_thresh}
            if args.watermark_rects:
                rect_list = []
                for r in args.watermark_rects.split(';'):
                    rect_list.append(list(map(int, r.split(','))))
                kwargs["rects"] = rect_list
                img = remove_watermark(img, mask_type="rect", **kwargs)
            else:
                img = remove_watermark(img, mask_type="color", **kwargs)

        # 2. 去背景处理
        cleaned = clean_sprite(img, args.tolerance, args.despill)
        if cleaned is not None:
            processed_images.append(cleaned)
            h, w = cleaned.shape[:2]
            max_w = max(max_w, w)
            max_h = max(max_h, h)

    if not processed_images:
        print("没有成功处理任何图片。")
        sys.exit(1)

    # 计算最终 SpriteSheet 的尺寸
    num_imgs = len(processed_images)
    cols = min(args.cols, num_imgs)
    rows = (num_imgs + cols - 1) // cols
    
    sheet_w = cols * max_w
    sheet_h = rows * max_h
    
    print(f"原始拼接尺寸: {sheet_w} x {sheet_h}")

    # 创建原始比例画布 (透明)
    sprite_sheet = np.zeros((sheet_h, sheet_w, 4), dtype=np.uint8)

    # 拼接图片
    for i, img in enumerate(processed_images):
        r = i // cols
        c = i % cols
        
        h, w = img.shape[:2]
        # 居中放置 (如果图片尺寸不一)
        y_offset = r * max_h + (max_h - h) // 2
        x_offset = c * max_w + (max_w - w) // 2
        
        sprite_sheet[y_offset:y_offset+h, x_offset:x_offset+w] = img

    # --- 缩放处理逻辑 (已恢复) ---
    final_output = sprite_sheet
    if sheet_w > args.max_size or sheet_h > args.max_size:
        scale = min(args.max_size / sheet_w, args.max_size / sheet_h)
        new_w = int(sheet_w * scale)
        new_h = int(sheet_h * scale)
        print(f"检测到尺寸超出 {args.max_size}，正在应用整体 RGBA 缩放 (Scale: {scale:.2f})...")
        
        # 按照用户要求：RGBA 四通道整体再缩放，禁止通道分开处理
        # 直接使用 INTER_AREA 进行整体缩放，不分离 Alpha
        final_output = cv2.resize(sprite_sheet, (new_w, new_h), interpolation=cv2.INTER_AREA)
        
        print(f"最终输出尺寸: {new_w} x {new_h}")

    # 保存结果
    cv2_imwrite(args.output_file, final_output)
    print(f"\n处理完成!")
    print(f"输出文件: {args.output_file}")
    print(f"布局: {rows} 行 x {cols} 列")

if __name__ == '__main__':
    main()
