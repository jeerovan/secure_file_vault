import jwt
import json
import base64
import time

def view_jwt_contents(token: str) -> dict:
    """
    Decodes a JWT to view its header and payload without verification.
    WARNING: For debugging/inspection only. DO NOT use for authentication.
    """
    try:
        parts = token.split('.')
        if len(parts) != 3:
            return {"error": "Invalid token structure."}
        
        # Decode header
        header_b64 = parts[0]
        header_bytes = base64.urlsafe_b64decode(header_b64 + '==')
        header = json.loads(header_bytes)

        # Decode payload
        payload_b64 = parts[1]
        payload_bytes = base64.urlsafe_b64decode(payload_b64 + '==')
        payload = json.loads(payload_bytes)

        # Show human-readable expiration time
        if 'exp' in payload:
            payload['exp_readable'] = time.ctime(payload['exp'])

        return {"header": header, "payload": payload}
    
    except Exception as e:
        return {"error": f"Failed to decode token: {e}"}


def verify_and_decode_jwt(token: str, secret_key: str) -> dict:
    """
    Verifies the JWT's signature and claims using the secret key.
    This is the secure method for authenticating a user.
    """
    try:
        # jwt.decode() handles signature verification and expiration check
        decoded_payload = jwt.decode(
            token, 
            secret_key, 
            algorithms=["HS256","ES256"]
        )
        return {"valid": True, "payload": decoded_payload}
    
    except jwt.ExpiredSignatureError:
        return {"valid": False, "error": "Token has expired."}
    
    except jwt.InvalidSignatureError:
        return {"valid": False, "error": "Invalid signature. Key is incorrect or token has been tampered with."}
    
    except jwt.InvalidTokenError as e:
        return {"valid": False, "error": f"Invalid token: {e}"}


# --- Example Usage ---

# IMPORTANT: Replace these with your actual accessToken and Supabase JWT secret
ACCESS_TOKEN = """eyJhbGciOiJIUzI1NiIsImtpZCI6IjRnSFdCMlBOS0grV25EdzkiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2VsZ3BjeHpyaGhtdGxpeG1wcXhwLnN1cGFiYXNlLmNvL2F1dGgvdjEiLCJzdWIiOiI0YWJiY2M1Yi1kNjIzLTRmOGQtODRkNS01NDVjYjY3ZWM4MDkiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzYyMDU1OTIxLCJpYXQiOjE3NjIwNTIzMjEsImVtYWlsIjoiamVldmFuMjM4NUBnbWFpbC5jb20iLCJwaG9uZSI6IiIsImFwcF9tZXRhZGF0YSI6eyJwcm92aWRlciI6ImVtYWlsIiwicHJvdmlkZXJzIjpbImVtYWlsIl19LCJ1c2VyX21ldGFkYXRhIjp7ImVtYWlsIjoiamVldmFuMjM4NUBnbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwicGhvbmVfdmVyaWZpZWQiOmZhbHNlLCJzdWIiOiI0YWJiY2M1Yi1kNjIzLTRmOGQtODRkNS01NDVjYjY3ZWM4MDkifSwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJvdHAiLCJ0aW1lc3RhbXAiOjE3NjIwNTIzMjF9XSwic2Vzc2lvbl9pZCI6IjJjNTg0OGU5LTc4OWYtNGJmZi05MmRiLWJjNjcyYmE0Y2E2MiIsImlzX2Fub255bW91cyI6ZmFsc2V9.Bb2I5BwvkbOgeKvcC_Y8NUxAaBmQMFe-jKPYsz7FUd4"""

JWT_SECRET_KEY = "6c58478e-0f88-4cb4-9853-d70f7c107cb5"

# --- 1. Viewing Token Contents (for debugging) ---
print("--- Viewing JWT Contents (Unverified) ---")
unverified_contents = view_jwt_contents(ACCESS_TOKEN)
print(json.dumps(unverified_contents, indent=2))
print("-" * 40)


# --- 2. Verifying the Token (for authentication) ---
print("--- Verifying JWT Signature ---")
verification_result = verify_and_decode_jwt(ACCESS_TOKEN, JWT_SECRET_KEY)
print(json.dumps(verification_result, indent=2))
print("-" * 40)


