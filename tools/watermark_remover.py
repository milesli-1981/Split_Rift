import cv2
import numpy as np
import argparse
import os
import sys

def cv2_imread(file_path):
    return cv2.imdecode(np.fromfile(file_path, dtype=np.uint8), cv2.IMREAD_UNCHANGED)

def cv2_imwrite(file_path, img):
    cv2.imencode('.png', img)[1].tofile(file_path)

def remove_watermark(img, mask_type="color", **kwargs):
    """
    高级去水印修复
    """
    if img is None:
        return None

    h, w = img.shape[:2]
    
    # 提取 BGR 通道
    has_alpha = img.shape[2] == 4
    if has_alpha:
        bgr = img[:, :, :3].copy()
        alpha = img[:, :, 3].copy()
    else:
        bgr = img.copy()

    mask = np.zeros((h, w), np.uint8)

    if mask_type == "color":
        # 1. 转换到 HSV 空间，对亮度 (V) 更加敏感，适合半透明水印
        hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
        v_channel = hsv[:, :, 2]
        
        # 默认认为水印是高亮色 (V > 200)
        v_thresh = kwargs.get("v_thresh", 200)
        _, mask = cv2.threshold(v_channel, v_thresh, 255, cv2.THRESH_BINARY)
        
        # 2. 结合 S 通道（饱和度）过滤，水印通常饱和度较低（接近白/灰）
        s_channel = hsv[:, :, 1]
        s_thresh = kwargs.get("s_thresh", 50)
        _, s_mask = cv2.threshold(s_channel, s_thresh, 255, cv2.THRESH_BINARY_INV)
        
        mask = cv2.bitwise_and(mask, s_mask)
        
    elif mask_type == "rect":
        rects = kwargs.get("rects", [])
        for (rx, ry, rw, rh) in rects:
            cv2.rectangle(mask, (rx, ry), (rx + rw, ry + rh), 255, -1)
    
    # --- 蒙版优化 ---
    if np.sum(mask) > 0:
        # 膨胀蒙版：确保覆盖水印的半透明边缘
        kernel = np.ones((3, 3), np.uint8)
        mask = cv2.dilate(mask, kernel, iterations=1)
        
        # 使用 Inpainting 修复
        # 修复半径设为 5，效果更平滑
        result_bgr = cv2.inpaint(bgr, mask, 5, cv2.INPAINT_TELEA)
    else:
        result_bgr = bgr

    if has_alpha:
        result = cv2.cvtColor(result_bgr, cv2.COLOR_BGR2BGRA)
        result[:, :, 3] = alpha
        return result
    else:
        return result_bgr

def main():
    parser = argparse.ArgumentParser(description="Watermark Remover Tool")
    parser.add_argument("input", help="输入图片路径")
    parser.add_argument("output", help="输出图片路径")
    parser.add_argument("--type", choices=["color", "rect"], default="color", help="蒙版类型")
    parser.add_argument("--rects", help="矩形区域 (x,y,w,h;...)")
    parser.add_argument("--v_thresh", type=int, default=180, help="亮度阈值 (0-255, 越低覆盖越多)")
    
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"错误: 找不到文件 {args.input}")
        sys.exit(1)

    img = cv2_imread(args.input)
    
    kwargs = {"v_thresh": args.v_thresh}
    if args.type == "rect" and args.rects:
        rect_list = []
        for r in args.rects.split(';'):
            rect_list.append(list(map(int, r.split(','))))
        kwargs["rects"] = rect_list

    result = remove_watermark(img, args.type, **kwargs)
    cv2_imwrite(args.output, result)
    print(f"水印处理完成: {args.output}")

if __name__ == '__main__':
    main()
