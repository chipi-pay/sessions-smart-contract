#!/bin/bash

FORWARDER="0x02a2554b645eee6b072b3118ee4bf9f3e92654d7a5f048452ca0b03e02ee682a"

RELAYER1="0x78d4af0f377f33a81b5385293397fdf33881ec22b72cc73024ff70e19f0cf42"
RELAYER2="0x65e67f3337ce0b2f50dd1b1845b8cb065f29293e1095d214b9261c74c5bb61a"
RELAYER3="0x4d3801067acd63ef9a94b5bfb4a8f206507f1880c20c31d844281f6b6f17308"

echo "Whitelisting relayers in forwarder..."
echo "Forwarder: $FORWARDER"
echo ""

echo "[1/3] Whitelisting relayer 1..."
sncast invoke --contract-address $FORWARDER --function add_to_whitelist --arguments $RELAYER1 --network mainnet --account deployer_oz 2>&1 | grep -E "(command:|Transaction|Success|Error)" || echo "Done"

echo ""
echo "[2/3] Whitelisting relayer 2..."
sncast invoke --contract-address $FORWARDER --function add_to_whitelist --arguments $RELAYER2 --network mainnet --account deployer_oz 2>&1 | grep -E "(command:|Transaction|Success|Error)" || echo "Done"

echo ""
echo "[3/3] Whitelisting relayer 3..."
sncast invoke --contract-address $FORWARDER --function add_to_whitelist --arguments $RELAYER3 --network mainnet --account deployer_oz 2>&1 | grep -E "(command:|Transaction|Success|Error)" || echo "Done"

echo ""
echo "✅ Whitelisting complete!"
