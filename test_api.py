#!/usr/bin/env python3
import json
import requests
import sys

# Obtenir un token d'authentification
login_response = requests.post(
    "http://localhost:9443/auth/login",
    json={"email": "test@example.com", "password": "Test1234!"},
    headers={"Content-Type": "application/json"}
)

print("Login response status:", login_response.status_code)
print("Login response content:", login_response.text)

if login_response.status_code != 200:
    sys.exit(1)

token = login_response.json().get("token")
print("Token:", token)

# Tester l'endpoint /me
me_response = requests.get(
    "http://localhost:9443/me",
    headers={"Authorization": f"Bearer {token}"}
)

print("ME response status:", me_response.status_code)
print("ME response content:", me_response.text)

# Tester d'autres endpoints
user_response = requests.get(
    "http://localhost:9443/user/",
    headers={"Authorization": f"Bearer {token}"}
)

print("USER response status:", user_response.status_code)
print("USER response content:", user_response.text)

game_response = requests.get(
    "http://localhost:9443/game/",
    headers={"Authorization": f"Bearer {token}"}
)

print("GAME response status:", game_response.status_code)
print("GAME response content:", game_response.text)

auth_response = requests.get(
    "http://localhost:9443/auth/",
    headers={"Authorization": f"Bearer {token}"}
)

print("AUTH response status:", auth_response.status_code)
print("AUTH response content:", auth_response.text)
