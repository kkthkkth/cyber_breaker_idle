import os
import cv2
import numpy as np
from PIL import Image

def process_sprite_sheet(image_path, output_dir):
    img = cv2.imread(image_path)
    if img is None:
        return

    H, W = img.shape[:2]
    filename = os.path.splitext(os.path.basename(image_path))[0]
    print(f"[{filename}] 찐막! 배경은 지우고 얼굴은 완벽 보호하는 누끼 시작...")

    # 기하학적 4행 분할 (비율 불변)
    y_bounds = [
        (0, int(H * 0.31)),
        (int(H * 0.31), int(H * 0.54)),
        (int(H * 0.54), int(H * 0.77)),
        (int(H * 0.77), H)
    ]

    frame_idx = 1
    for row_idx, (y1, y2) in enumerate(y_bounds):
        cols = 3 if row_idx == 0 else 5
        col_w = W / cols

        for c in range(cols):
            x1 = int(c * col_w)
            x2 = int((c + 1) * col_w)

            cell_img = img[y1:y2, x1:x2]

            if cell_img.shape[0] < 10 or cell_img.shape[1] < 10:
                frame_idx += 1
                continue

            # 1. 흑백으로 변환하여 하얀색 찾기
            gray = cv2.cvtColor(cell_img, cv2.COLOR_BGR2GRAY)
            
            # 230 이상 밝은 곳(배경, 얼굴 등)은 흰색(255), 나머지는 검은색(0)
            _, binary_white = cv2.threshold(gray, 230, 255, cv2.THRESH_BINARY)

            # 2. 방해되는 보라색 표(Grid) 선을 무시하기 위해, 칸의 가장자리 3픽셀을 강제로 하얗게 뚫어버림
            # 이렇게 하면 모든 배경이 하나로 뻥 뚫린 '바다'가 됨
            bw_h, bw_w = binary_white.shape
            binary_white[0:3, :] = 255
            binary_white[-3:, :] = 255
            binary_white[:, 0:3] = 255
            binary_white[:, -3:] = 255

            # 3. 맨 위 구석(0,0)에서부터 투명화 잉크(128) 붓기! 
            # 캐릭터 테두리가 댐 역할을 해서 얼굴(255)은 무사함!
            flood_mask = np.zeros((bw_h + 2, bw_w + 2), np.uint8)
            cv2.floodFill(binary_white, flood_mask, (0, 0), 128)

            # 4. 잉크가 묻은 곳(128)만 투명(0)으로, 나머지는 불투명(255)으로 설정
            final_alpha = np.where(binary_white == 128, 0, 255).astype(np.uint8)

            # 5. 원본 BGR 이미지에 완벽한 투명도 적용
            rgba = cv2.cvtColor(cell_img, cv2.COLOR_BGR2BGRA)
            rgba[:, :, 3] = final_alpha

            # 6. 투명한 여백 바짝 잘라내기
            coords = cv2.findNonZero(final_alpha)
            if coords is not None:
                cx, cy, cw, ch = cv2.boundingRect(coords)

                # 유의미한 크기의 캐릭터/투사체만 저장
                if cw > 15 and ch > 15:
                    pad = 3
                    cx1 = max(0, cx - pad)
                    cy1 = max(0, cy - pad)
                    cx2 = min(rgba.shape[1], cx + cw + pad)
                    cy2 = min(rgba.shape[0], cy + ch + pad)

                    final_crop = rgba[cy1:cy2, cx1:cx2]
                    final_rgba = cv2.cvtColor(final_crop, cv2.COLOR_BGRA2RGBA)
                    final_pil = Image.fromarray(final_rgba)

                    save_path = os.path.join(output_dir, f"{filename}_frame_{frame_idx:02d}.png")
                    final_pil.save(save_path)

            frame_idx += 1

def process_nested_folders(target_root_dir):
    valid_exts = ('.png', '.jpg', '.jpeg')
    print("얼굴은 살리고 배경만 완벽하게 도려내는 파이프라인 가동...")

    for root, dirs, files in os.walk(target_root_dir):
        for file in files:
            if file.lower().endswith(valid_exts):
                if "_frame_" in file:
                    continue
                full_path = os.path.join(root, file)
                process_sprite_sheet(full_path, root)

if __name__ == '__main__':
    import sys
    target_dir = sys.argv[1] if len(sys.argv) > 1 else 'assets/images/UR'
    process_nested_folders(target_dir)
    print("모든 작업이 완벽하게 완료되었습니다!")