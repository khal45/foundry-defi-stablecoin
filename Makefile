-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

fmt-build:; forge fmt && forge build

coverage:; forge coverage --report debug > coverage.txt

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

chain ?= anvil
fork_url := $(if $(filter $(chain),anvil),http://127.0.0.1:8545,$(SEPOLIA_RPC_URL))
account := $(if $(filter $(chain),anvil),keyOne,devWallet)
verify_flags := $(if $(filter $(chain),sepolia),--verify --etherscan-api-key $(ETHERSCAN_API_KEY),)

deploy-DecentralizedStableCoin: 
	forge script script/DeployDecentralizedStableCoin.s.sol:DeployDecentralizedStableCoin --fork-url $(fork_url) --account $(account) --broadcast $(verify_flags) -vvvv