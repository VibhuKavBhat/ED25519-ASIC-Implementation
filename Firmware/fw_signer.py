import os
import sys
import argparse
import hashlib
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

def rev_hex(byte_array):
    """Reverses byte array for SystemVerilog Big-Endian parsing."""
    return byte_array[::-1].hex()

def generate_keys(priv_path="fw_key.priv", pub_path="fw_key.pub"):
    """Generates and saves a new Ed25519 keypair."""
    private_key = ed25519.Ed25519PrivateKey.generate()
    
    # Save Private Key
    with open(priv_path, "wb") as f:
        f.write(private_key.private_bytes_raw())
        
    # Save Public Key
    with open(pub_path, "wb") as f:
        f.write(private_key.public_key().public_bytes_raw())
        
    print(f"[+] Keys generated: {priv_path}, {pub_path}")
    return private_key

def sign_firmware(fw_path, priv_path):
    """Signs firmware and outputs SystemVerilog constants."""
    if not os.path.exists(fw_path):
        print(f"[-] Error: Firmware '{fw_path}' not found.")
        return
        
    with open(fw_path, "rb") as f:
        firmware_msg = f.read()
        
    with open(priv_path, "rb") as f:
        priv_bytes = f.read()
        private_key = ed25519.Ed25519PrivateKey.from_private_bytes(priv_bytes)

    public_key = private_key.public_key()
    pub_bytes = public_key.public_bytes_raw()

    # Sign the firmware
    signature = private_key.sign(firmware_msg)
    R_bytes = signature[:32]
    s_bytes = signature[32:]

    # Calculate SHA-512(R || A || M)
    digest = hashlib.sha512()
    digest.update(R_bytes)
    digest.update(pub_bytes)
    digest.update(firmware_msg)
    hash_result = digest.digest()

    print(f"\n// {'='*60}")
    print(f"// AUTO-GENERATED ED25519 TEST VECTOR FOR: {fw_path}")
    print(f"// FIRMWARE SIZE: {len(firmware_msg)} bytes")
    print(f"// {'='*60}")
    print(f"localparam logic [255:0] FW_PUB_KEY = \n    256'h{rev_hex(pub_bytes)};\n")
    print(f"localparam logic [255:0] FW_SIG_R = \n    256'h{rev_hex(R_bytes)};\n")
    print(f"localparam logic [255:0] FW_SIG_S = \n    256'h{rev_hex(s_bytes)};\n")
    print(f"localparam logic [255:0] FW_HASH_LO = \n    256'h{rev_hex(hash_result[:32])};\n")
    print(f"localparam logic [255:0] FW_HASH_HI = \n    256'h{rev_hex(hash_result[32:])};")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ed25519 Firmware Signer for ASIC")
    parser.add_argument("firmware", help="Path to the firmware binary (.bin)")
    parser.add_argument("--keygen", action="store_true", help="Generate new keys before signing")
    parser.add_argument("--key", default="fw_key.priv", help="Path to private key (default: fw_key.priv)")
    
    args = parser.parse_args()
    
    if args.keygen or not os.path.exists(args.key):
        generate_keys(args.key, args.key.replace(".priv", ".pub"))
        
    sign_firmware(args.firmware, args.key)