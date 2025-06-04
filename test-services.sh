#!/bin/bash

echo "Testing Gateway Service..."
curl -v http://localhost:9443/
echo -e "\n\n"

echo "Testing Auth Service..."
curl -v http://localhost:9443/auth/
echo -e "\n\n"

echo "Testing User Service..."
curl -v http://localhost:9443/user/
echo -e "\n\n"

echo "Testing Game Service..."
curl -v http://localhost:9443/game/
echo -e "\n\n"
