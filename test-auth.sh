#!/bin/bash

# Tester l'enregistrement et l'authentification
register_response=$(curl -s -X POST http://localhost:9443/auth/register -H "Content-Type: application/json" -d '{"email":"test@example.com","password":"Test1234!","username":"testuser"}')
echo "Register response: $register_response"
echo

# Tenter de s'authentifier
login_response=$(curl -s -X POST http://localhost:9443/auth/login -H "Content-Type: application/json" -d '{"email":"test@example.com","password":"Test1234!"}')
echo "Login response: $login_response"
echo

# Extraire le token (cette ligne suppose que le token est dans le format {"token":"..."}
token=$(echo $login_response | grep -o '"token":"[^"]*' | cut -d'"' -f4)
echo "Extracted token: $token"
echo

if [ -n "$token" ]; then
  # Tester l'accès à la route racine avec le token
  echo "Testing root endpoint with token..."
  curl -v -H "Authorization: Bearer $token" http://localhost:9443/
  echo -e "\n\n"

  # Tester l'accès au service user avec le token
  echo "Testing user service with token..."
  curl -v -H "Authorization: Bearer $token" http://localhost:9443/user/
  echo -e "\n\n"

  # Tester l'accès au service game avec le token
  echo "Testing game service with token..."
  curl -v -H "Authorization: Bearer $token" http://localhost:9443/game/
  echo -e "\n\n"
else
  echo "No token extracted. Authentication may have failed."
fi
