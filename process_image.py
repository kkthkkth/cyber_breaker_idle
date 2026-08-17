import sys
from rembg import remove
from PIL import Image

def remove_bg(input_path, output_path):
    input_img = Image.open(input_path)
    output_img = remove(input_img)
    output_img.save(output_path)
    print(f"배경 제거 완료: {output_path}")

if __name__ == "__main__":
    # 사용법: python process_image.py input.png output.png
    remove_bg(sys.argv[1], sys.argv[2])