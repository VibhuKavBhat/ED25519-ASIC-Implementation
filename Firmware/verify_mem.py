from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.exceptions import InvalidSignature

def verify_mem_file(filename="firmware.mem"):
    print(f"Parsing {filename}...\n")
    
    with open(filename, "r") as f:
        lines = f.readlines()
        
    # Extract just the hex part of each line (split by the '//' comment)
    words = [line.split("//")[0].strip() for line in lines if line.strip()]
    
    if len(words) < 26:
        print("Error: Not enough words in memory file.")
        return

    # word[0] is the length, skip it for data extraction
    S_hex      = "".join(words[1:9])
    R_hex      = "".join(words[9:17])
    PubKey_hex = "".join(words[17:25])
    Msg_hex    = "".join(words[25:])
    
    print(f"S      : {S_hex}")
    print(f"R      : {R_hex}")
    print(f"PubKey : {PubKey_hex}")
    
    # Try to decode the message to text so we can see what was actually packed
    msg_bytes = bytes.fromhex(Msg_hex)
    try:
        print(f"Message: {msg_bytes.decode('utf-8')}")
    except:
        print(f"Message: (Raw Hex) {Msg_hex}")

    # Ed25519 signature is R concatenated with S
    signature_bytes = bytes.fromhex(R_hex + S_hex)
    public_key_bytes = bytes.fromhex(PubKey_hex)
    
    print("\n---------------------------------------------------")
    print(" Asking Python to verify this exact memory payload...")
    print("---------------------------------------------------")
    
    try:
        public_key = ed25519.Ed25519PublicKey.from_public_bytes(public_key_bytes)
        public_key.verify(signature_bytes, msg_bytes)
        print("🚨 PYTHON SAYS: SIGNATURE IS VALID!")
        print("   Conclusion: Your generator script did NOT pack the hack properly.")
    except InvalidSignature:
        print("✅ PYTHON SAYS: SIGNATURE IS INVALID!")
        print("   Conclusion: The hack is packed correctly. Your Verilog hardware is falsely passing it!")
    except Exception as e:
        print(f"Error during verification: {e}")

if __name__ == "__main__":
    verify_mem_file()