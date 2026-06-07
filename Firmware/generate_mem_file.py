import textwrap
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

def chunk_to_32bit_words(hex_str):
    """Pads the hex string to be a multiple of 8 chars (32 bits) and splits it."""
    # Split into list of 8-character strings
    return textwrap.wrap(hex_str, 8)

def generate_mem_file(filename="firmware.mem"):
    # ---------------------------------------------------------
    # 1. Generate Ed25519 Keypair & Sign Message
    # ---------------------------------------------------------
    print("Generating Ed25519 Keypair...")
    private_key = ed25519.Ed25519PrivateKey.generate()
    public_key = private_key.public_key()
    
    # Extract raw 32-byte public key
    pubkey_bytes = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )

    # Define the firmware message
    message_bytes = b"Hello, ED25519 FPGA Demo! This is a dummy firmware message(:"
    
    # Sign the message
    # In Ed25519, the signature is 64 bytes total: 32 bytes for R, 32 bytes for S
    signature_bytes = private_key.sign(message_bytes)

    # =================================================================
    # !HACKER INTERVENTION!
    # Let's tamper with the firmware payload AFTER it was signed!
    # Ensure it is the exact same length so the 32-bit chunking doesn't shift.
    message_bytes = b"Hello, ED25519 FPGA Demo! This is a HACKED! firmware message(:"
    # =================================================================
    
    # Extract R and S
    R_bytes = signature_bytes[:32]
    S_bytes = signature_bytes[32:]

    # Convert to hex strings
    S_hex = S_bytes.hex()
    R_hex = R_bytes.hex()
    PubKey_hex = pubkey_bytes.hex()
    message_hex = message_bytes.hex()

    print(f"Signature (R): {R_hex}")
    print(f"Signature (S): {S_hex}")
    print(f"Public Key   : {PubKey_hex}")

    # ---------------------------------------------------------
    # 2. Chunk Data into 32-bit Words
    # ---------------------------------------------------------
    S_words      = chunk_to_32bit_words(S_hex)
    R_words      = chunk_to_32bit_words(R_hex)
    PubKey_words = chunk_to_32bit_words(PubKey_hex)
    Msg_words    = chunk_to_32bit_words(message_hex)

    # ---------------------------------------------------------
    # 3. Calculate SHA-512 Feeding Length
    # ---------------------------------------------------------
    # For Ed25519 verification, the SHA-512 hash input is: R || PubKey || Message
    total_sha_words = len(R_words) + len(PubKey_words) + len(Msg_words)

    # ---------------------------------------------------------
    # 4. Write to .mem file
    # ---------------------------------------------------------
    with open(filename, "w") as f:
        # Address 0: Total length of (R + PubKey + Msg) in 32-bit words
        f.write(f"{total_sha_words:08x} // [0] Total SHA words\n")
        
        # Address 1 to 8: Signature S (8 words = 32 bytes)
        for i, w in enumerate(S_words):
            f.write(f"{w} // [{i+1}] S word {i}\n")
            
        # Address 9 to 16: Signature R (8 words = 32 bytes)
        for i, w in enumerate(R_words):
            f.write(f"{w} // [{i+9}] R word {i}\n")
            
        # Address 17 to 24: Public Key (8 words = 32 bytes)
        for i, w in enumerate(PubKey_words):
            f.write(f"{w} // [{i+17}] PubKey word {i}\n")
            
        # Address 25+: Message
        for i, w in enumerate(Msg_words):
            f.write(f"{w} // [{i+25}] Message word {i}\n")

    print(f"\nSuccessfully generated {filename}")
    print(f" -> Total BRAM size used: {1 + len(S_words) + total_sha_words} words")
    print(f" -> Ready for FPGA simulation!")

if __name__ == "__main__":
    generate_mem_file()