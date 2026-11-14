"""
EXIF-orientation normalization and HEIC conversion for uploaded frames/images.
"""
from PIL import Image, ImageOps
import os

# Register HEIC/HEIF support if the library is available
try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
    print("[INFO] HEIC/HEIF support enabled via pillow-heif.")
except ImportError:
    print("[WARN] pillow-heif is not installed. HEIC files will fail to load. "
          "Please run: pip install pillow-heif")

def normalize_and_convert(image_path: str, target_ext: str = ".jpg") -> str:
    """
    Opens the image (supports HEIC if pillow-heif is installed),
    bakes EXIF rotation into the pixel data, converts to RGB,
    and saves it as a standard JPEG.
    
    Returns the path to the new JPEG file.
    """
    base, ext = os.path.splitext(image_path)
    new_path = base + target_ext
    
    try:
        with Image.open(image_path) as img:
            # Convert to RGB (handles RGBA, P, or CMYK modes)
            if img.mode != "RGB":
                img = img.convert("RGB")
                
            # exif_transpose physically rotates/flips pixels to match the orientation tag
            fixed = ImageOps.exif_transpose(img)
            if fixed is None:
                fixed = img
                
            # Save as JPEG
            fixed.save(new_path, "JPEG", quality=95)
            
            # If we changed the extension, remove the original file
            if new_path != image_path and os.path.exists(image_path):
                try:
                    os.remove(image_path)
                except OSError:
                    pass
                    
            return new_path
            
    except Exception as e:
        print(f"  [warn] Image processing failed for {image_path}: {e}")
        return image_path
    
    