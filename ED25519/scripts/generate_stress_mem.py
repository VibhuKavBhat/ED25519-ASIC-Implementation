import os
import hashlib
import random
from cryptography.hazmat.primitives.asymmetric import ed25519

def rev_hex(byte_array):
    return byte_array[::-1].hex()

NUM_VECTORS = 1000
with open("stress_vectors.mem", "w") as f:
    for i in range(NUM_VECTORS):
        private_key = ed25519.Ed25519PrivateKey.generate()
        pub_bytes = private_key.public_key().public_bytes_raw()
        msg = os.urandom(64) # Random 64-byte message
        
        # Generate genuine signature
        sig = private_key.sign(msg)
        
        # 50/50 Chance to be a Valid or Invalid test case
        is_valid = random.choice([True, False])
        
        if not is_valid:
            corruption_type = random.choice(['bad_sig', 'bad_pubkey', 'bad_msg'])
            if corruption_type == 'bad_sig':
                # Corrupt the signature by flipping a byte
                sig = bytes([sig[0] ^ 0xFF]) + sig[1:]
            elif corruption_type == 'bad_pubkey':
                # Swap the public key for a stranger's key
                pub_bytes = ed25519.Ed25519PrivateKey.generate().public_key().public_bytes_raw()
            elif corruption_type == 'bad_msg':
                # Tamper with the message before hashing it
                msg = os.urandom(64) 
                
        R_bytes, s_bytes = sig[:32], sig[32:]
        hash_res = hashlib.sha512(R_bytes + pub_bytes + msg).digest()
        
        # Add a 1-byte flag at the front: "01" for valid, "00" for invalid
        flag_hex = "01" if is_valid else "00"
        
        # Write exactly 1288 bits per line (Flag + Pub + R + S + Hash)
        # No underscores, just pure contiguous hex so $readmemh parses it perfectly
        line = f"{flag_hex}{rev_hex(pub_bytes)}{rev_hex(R_bytes)}{rev_hex(s_bytes)}{rev_hex(hash_res[:32])}{rev_hex(hash_res[32:])}\n"
        f.write(line)

print(f"[+] Generated {NUM_VECTORS} vectors (Approx 50% Valid / 50% Invalid)")