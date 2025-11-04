import jwt
import requests
import json
from jwt.algorithms import ECAlgorithm
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

class SupabaseJWTVerifier:
    """
    Verifies Supabase JWT tokens signed with ES256 (P-256 elliptic curve).
    Uses the public JWKS endpoint to fetch verification keys.
    """
    
    def __init__(self, project_url: str):
        """
        Initialize the verifier with your Supabase project URL.
        
        Args:
            project_url: Your Supabase project URL (e.g., "https://xxxxx.supabase.co")
        """
        self.project_url = project_url.rstrip('/')
        self.jwks_url = f"{self.project_url}/auth/v1/.well-known/jwks.json"
        self.jwks_cache = None
    
    def fetch_jwks(self):
        """
        Fetches the JSON Web Key Set (JWKS) from Supabase.
        """
        try:
            response = requests.get(self.jwks_url)
            response.raise_for_status()
            self.jwks_cache = response.json()
            return self.jwks_cache
        except Exception as e:
            raise Exception(f"Failed to fetch JWKS: {e}")
    
    def get_signing_key(self, token: str):
        """
        Extracts the signing key from JWKS based on the kid in the token header.
        """
        if not self.jwks_cache:
            self.fetch_jwks()
        
        # Decode header without verification to get kid
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get('kid')
        
        if not kid:
            raise Exception("Token missing 'kid' in header")
        
        # Find the matching key in JWKS
        for key in self.jwks_cache.get('keys', []):
            if key.get('kid') == kid:
                return key
        
        raise Exception(f"No matching key found for kid: {kid}")
    
    def jwk_to_pem(self, jwk: dict) -> str:
        """
        Converts a JWK to PEM format for verification.
        """
        try:
            # Use PyJWT's built-in JWK conversion
            public_key = jwt.PyJWK(jwk).key
            
            # Convert to PEM format
            pem = public_key.public_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PublicFormat.SubjectPublicKeyInfo
            )
            return pem
        except Exception as e:
            raise Exception(f"Failed to convert JWK to PEM: {e}")
    
    def verify_token(self, token: str, audience: str = "authenticated") -> dict:
        """
        Verifies a Supabase JWT token signed with ES256.
        
        Args:
            token: The JWT access token from Supabase
            audience: Expected audience claim (default: "authenticated")
        
        Returns:
            dict: {"valid": True, "payload": decoded_payload} or 
                  {"valid": False, "error": error_message}
        """
        try:
            # Get the signing key from JWKS
            jwk = self.get_signing_key(token)
            
            # Convert JWK to PEM format
            public_key_pem = self.jwk_to_pem(jwk)
            
            # Verify and decode the token
            decoded_payload = jwt.decode(
                token,
                public_key_pem,
                algorithms=["ES256"],
                audience=audience,
                options={
                    "verify_signature": True,
                    "verify_exp": True,
                    "verify_aud": True
                }
            )
            
            return {"valid": True, "payload": decoded_payload}
        
        except jwt.ExpiredSignatureError:
            return {"valid": False, "error": "Token has expired"}
        
        except jwt.InvalidAudienceError:
            return {"valid": False, "error": f"Invalid audience. Expected: {audience}"}
        
        except jwt.InvalidSignatureError:
            return {"valid": False, "error": "Invalid signature. Token may be tampered with."}
        
        except jwt.InvalidTokenError as e:
            return {"valid": False, "error": f"Invalid token: {str(e)}"}
        
        except Exception as e:
            return {"valid": False, "error": f"Verification failed: {str(e)}"}
    
    def view_token_contents(self, token: str) -> dict:
        """
        Decodes the JWT to view its contents without verification.
        WARNING: For debugging only. DO NOT use for authentication.
        """
        try:
            header = jwt.get_unverified_header(token)
            payload = jwt.decode(token, options={"verify_signature": False})
            
            # Add readable timestamp
            if 'exp' in payload:
                import time
                payload['exp_readable'] = time.ctime(payload['exp'])
            
            return {"header": header, "payload": payload}
        
        except Exception as e:
            return {"error": f"Failed to decode token: {e}"}


# ===== EXAMPLE USAGE =====

if __name__ == "__main__":
    # Replace with your Supabase project URL
    SUPABASE_PROJECT_URL = "https://elgpcxzrhhmtlixmpqxp.supabase.co"
    
    # Replace with your JWT access token
    ACCESS_TOKEN = "eyJhbGciOiJFUzI1NiIsImtpZCI6IjYzMGNmMDUxLThmMmMtNDk5Zi05ZWUwLWRmMGYyZjQwMzAzNCIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2VsZ3BjeHpyaGhtdGxpeG1wcXhwLnN1cGFiYXNlLmNvL2F1dGgvdjEiLCJzdWIiOiI0YWJiY2M1Yi1kNjIzLTRmOGQtODRkNS01NDVjYjY3ZWM4MDkiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzYyMDY3NjA5LCJpYXQiOjE3NjIwNjQwMDksImVtYWlsIjoiamVldmFuMjM4NUBnbWFpbC5jb20iLCJwaG9uZSI6IiIsImFwcF9tZXRhZGF0YSI6eyJwcm92aWRlciI6ImVtYWlsIiwicHJvdmlkZXJzIjpbImVtYWlsIl19LCJ1c2VyX21ldGFkYXRhIjp7ImVtYWlsIjoiamVldmFuMjM4NUBnbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwicGhvbmVfdmVyaWZpZWQiOmZhbHNlLCJzdWIiOiI0YWJiY2M1Yi1kNjIzLTRmOGQtODRkNS01NDVjYjY3ZWM4MDkifSwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJvdHAiLCJ0aW1lc3RhbXAiOjE3NjIwNjQwMDl9XSwic2Vzc2lvbl9pZCI6ImRhOTJmMDA4LWZjN2ItNDI3YS1hMjY1LWNiMzBjNTc5NzY2OCIsImlzX2Fub255bW91cyI6ZmFsc2V9.vt6k6OUPISrHaXPTEg_rLzmQFmtUqavyoAdhAP5u5_4DZtlZuGOZnmRr-4tvjUYnSe3eeprk6pulikbTk0h89w"
    
    # Initialize verifier
    verifier = SupabaseJWTVerifier(SUPABASE_PROJECT_URL)
    
    # --- 1. View token contents (for debugging) ---
    print("=" * 60)
    print("VIEWING JWT CONTENTS (Unverified)")
    print("=" * 60)
    contents = verifier.view_token_contents(ACCESS_TOKEN)
    print(json.dumps(contents, indent=2))
    print()
    
    # --- 2. Verify the token (for authentication) ---
    print("=" * 60)
    print("VERIFYING JWT SIGNATURE (ES256)")
    print("=" * 60)
    result = verifier.verify_token(ACCESS_TOKEN, audience="authenticated")
    print(json.dumps(result, indent=2))
    print()
    
    if result.get("valid"):
        print("✓ Token is VALID")
        print(f"✓ User ID: {result['payload'].get('sub')}")
        print(f"✓ Email: {result['payload'].get('email')}")
    else:
        print(f"✗ Token is INVALID: {result.get('error')}")

