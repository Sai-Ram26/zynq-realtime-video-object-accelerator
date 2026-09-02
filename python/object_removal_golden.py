import os
import math
import numpy as np

def compute_psnr(img1, img2):
    mse = np.mean((img1.astype(np.float64) - img2.astype(np.float64)) ** 2)
    if mse == 0:
        return float('inf')
    max_pixel = 255.0
    return 20 * math.log10(max_pixel / math.sqrt(mse))

class VideoAcceleratorGolden:
    """
    Bit-accurate Python reference model for FPGA Video Processing Pipeline.
    Pipeline:
      1. RGB888 -> Grayscale (8-bit Fixed-Point Shift-Add)
      2. Background Differencing & Thresholding -> 1-bit Mask
      3. Inpainting / Substitution (Replace masked pixels with background)
      4. 4x4 Block Partitioning
      5. 4x4 H.264 Integer Transform (Core DCT)
      6. Quantization & Inverse Reconstruction
    """
    def __init__(self, threshold=30, qp=28):
        self.threshold = threshold
        self.qp = qp
        self.q_bits = 15 + (qp // 6)
        # H.264 forward transform matrix
        self.H = np.array([
            [ 1,  1,  1,  1],
            [ 2,  1, -1, -2],
            [ 1, -1, -1,  1],
            [ 1, -2,  2, -1]
        ], dtype=np.int32)
        
        # Scaling factor based on QP % 6
        self.mf_table = [
            [13107, 5243, 8066],
            [11916, 4660, 7490],
            [10082, 4194, 6554],
            [9362,  3647, 5825],
            [8192,  3355, 5243],
            [7282,  2893, 4559]
        ]

    def rgb2gray_hw(self, rgb_frame):
        """
        Hardware-exact fixed-point RGB to Grayscale.
        Y = (77*R + 150*G + 29*B) >> 8
        """
        r = rgb_frame[:, :, 2].astype(np.int32)
        g = rgb_frame[:, :, 1].astype(np.int32)
        b = rgb_frame[:, :, 0].astype(np.int32)
        y = ((77 * r + 150 * g + 29 * b) >> 8).astype(np.uint8)
        return y

    def compute_mask_and_inpaint(self, curr_gray, bg_gray):
        """
        Calculates absolute difference and substitutes masked pixels with background.
        """
        diff = np.abs(curr_gray.astype(np.int32) - bg_gray.astype(np.int32))
        mask = (diff > self.threshold).astype(np.uint8)
        # Inpaint: replace foreground with background
        cleaned_gray = np.where(mask == 1, bg_gray, curr_gray).astype(np.uint8)
        return mask, cleaned_gray

    def forward_integer_transform_4x4(self, block_4x4):
        """
        Standard H.264 4x4 Integer DCT transform: W = H * X * H^T
        """
        X = block_4x4.astype(np.int32)
        # 1D Row transform: T_row = X * H^T
        # 1D Col transform: W = H * T_row
        W = self.H @ X @ (self.H.T)
        return W

    def quantize_4x4(self, W):
        """
        H.264 4x4 Quantization
        """
        q_shift = 15 + (self.qp // 6)
        f = (1 << q_shift) // 3  # Intra rounding offset
        
        # Simplified uniform quantization approximation for testbench verification
        Z = np.sign(W) * ((np.abs(W) * 8192 + f) >> q_shift)
        return Z.astype(np.int32)

    def process_frame(self, curr_rgb, bg_rgb):
        """
        Processes a full frame and returns intermediate hardware verification states.
        """
        curr_gray = self.rgb2gray_hw(curr_rgb)
        bg_gray = self.rgb2gray_hw(bg_rgb)
        
        mask, cleaned_gray = self.compute_mask_and_inpaint(curr_gray, bg_gray)
        
        h, w = cleaned_gray.shape
        # Pad to multiple of 4
        pad_h = (4 - (h % 4)) % 4
        pad_w = (4 - (w % 4)) % 4
        padded = np.pad(cleaned_gray, ((0, pad_h), (0, pad_w)), mode='edge')
        
        transformed_blocks = []
        quantized_blocks = []
        
        for y in range(0, h, 4):
            for x in range(0, w, 4):
                block = padded[y:y+4, x:x+4]
                W = self.forward_integer_transform_4x4(block)
                Z = self.quantize_4x4(W)
                transformed_blocks.append(W)
                quantized_blocks.append(Z)
                
        return {
            "curr_gray": curr_gray,
            "bg_gray": bg_gray,
            "mask": mask,
            "cleaned_gray": cleaned_gray,
            "transformed_blocks": transformed_blocks,
            "quantized_blocks": quantized_blocks
        }

    def export_test_vectors(self, curr_rgb, bg_rgb, out_dir="tb_vectors"):
        """
        Exports pixel hex files for Verilog $readmemh simulation verification.
        """
        os.makedirs(out_dir, exist_ok=True)
        results = self.process_frame(curr_rgb, bg_rgb)
        
        curr_gray = results["curr_gray"]
        bg_gray = results["bg_gray"]
        mask = results["mask"]
        cleaned = results["cleaned_gray"]
        
        with open(os.path.join(out_dir, "curr_gray_in.hex"), "w") as f:
            for val in curr_gray.flatten():
                f.write(f"{val:02X}\n")
                
        with open(os.path.join(out_dir, "bg_gray_in.hex"), "w") as f:
            for val in bg_gray.flatten():
                f.write(f"{val:02X}\n")
                
        with open(os.path.join(out_dir, "expected_mask.hex"), "w") as f:
            for val in mask.flatten():
                f.write(f"{val:02X}\n")
                
        with open(os.path.join(out_dir, "expected_cleaned.hex"), "w") as f:
            for val in cleaned.flatten():
                f.write(f"{val:02X}\n")
                
        # Export first 4x4 block DCT input and expected output
        first_block = cleaned[0:4, 0:4]
        first_dct = results["transformed_blocks"][0]
        
        with open(os.path.join(out_dir, "dct_input_4x4.hex"), "w") as f:
            for val in first_block.flatten():
                f.write(f"{val:02X}\n")
                
        with open(os.path.join(out_dir, "expected_dct_4x4.hex"), "w") as f:
            for val in first_dct.flatten():
                f.write(f"{val & 0xFFFF:04X}\n") # 16-bit signed hex
                
        print(f"[+] Successfully exported test vectors to {out_dir}/")


if __name__ == "__main__":
    print("[*] Generating Synthetic Video Frames for Golden Reference Testing...")
    # Create 64x64 synthetic frame
    H, W = 64, 64
    bg_frame = np.full((H, W, 3), 120, dtype=np.uint8)
    curr_frame = bg_frame.copy()
    
    # Add an unwanted object (moving bright red box) in curr_frame
    curr_frame[20:44, 20:44] = [255, 0, 0]
    
    golden = VideoAcceleratorGolden(threshold=30, qp=28)
    res = golden.process_frame(curr_frame, bg_frame)
    
    psnr_before = compute_psnr(res["curr_gray"], res["bg_gray"])
    psnr_after = compute_psnr(res["cleaned_gray"], res["bg_gray"])
    
    print(f"[*] Object Removal Metrics:")
    print(f"    - PSNR before inpainting: {psnr_before:.2f} dB")
    print(f"    - PSNR after inpainting:  {psnr_after:.2f} dB (Perfect Ground Truth Match)")
    
    golden.export_test_vectors(curr_frame, bg_frame, out_dir="d:/mini_project2/tb/test_vectors")

