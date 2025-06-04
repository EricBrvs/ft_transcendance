#!/usr/bin/env python3
import json
import requests
import sys

# Désactiver les avertissements SSL
requests.packages.urllib3.disable_warnings()

# Obtenir un token d'authentification
login_response = requests.post(
    "http://localhost:9443/auth/login",
    json={"email": "test@example.com", "password": "Test1234!"},
    headers={"Content-Type": "application/json"},
    allow_redirects=True
)

print("\n===== LOGIN RESPONSE =====")
print("Status:", login_response.status_code)
print("Headers:", dict(login_response.headers))
print("Content:", login_response.text)

if login_response.status_code != 200:
    sys.exit(1)

token = login_response.json().get("token")
print("\nToken:", token)

# Tester l'endpoint /me
me_response = requests.get(
    "http://localhost:9443/me",
    headers={"Authorization": f"Bearer {token}"},
    allow_redirects=True
)

print("\n===== ME RESPONSE =====")
print("Status:", me_response.status_code)
print("Headers:", dict(me_response.headers))
print("Content:", me_response.text)

# Tester l'endpoint /user/
user_response = requests.get(
    "http://localhost:9443/user/",
    headers={"Authorization": f"Bearer {token}"},
    allow_redirects=True
)

print("\n===== USER RESPONSE =====")
print("Status:", user_response.status_code)
print("Headers:", dict(user_response.headers))
print("Content:", user_response.text)

# Tester l'endpoint /game/
game_response = requests.get(
    "http://localhost:9443/game/",
    headers={"Authorization": f"Bearer {token}"},
    allow_redirects=True
)

print("\n===== GAME RESPONSE =====")
print("Status:", game_response.status_code)
print("Headers:", dict(game_response.headers))
print("Content:", game_response.text)
