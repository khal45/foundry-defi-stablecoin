-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil

chain ?= anvil
fork_url := $(if $(filter $(chain),anvil),http://127.0.0.1:8545,$(SEPOLIA_RPC_URL))
account := $(if $(filter $(chain),anvil),keyOne,devWallet)
verify_flags := $(if $(filter $(chain),sepolia),--verify --etherscan-api-key $(ETHERSCAN_API_KEY),)

fmt-build:; forge fmt && forge build

coverage:; forge coverage --report debug > coverage.txt

test-sepolia:; forge test --fork-url $(SEPOLIA_RPC_URL) 

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.1.0  && forge install smartcontractkit/chainlink-brownie-contracts@0.6.1  && forge install foundry-rs/forge-std@v1.5.3  && forge install openzeppelin/openzeppelin-contracts@v4.8.3 

deploy-DecentralizedStableCoin: 
	forge script script/DeployDecentralizedStableCoin.s.sol:DeployDecentralizedStableCoin \
		--fork-url $(fork_url) --account $(account) --broadcast $(verify_flags) -vvvv

deploy-DSC:
	forge script script/DeployDSC.s.sol:DeployDSC \
		--fork-url $(fork_url) --account $(account) --broadcast $(verify_flags) -vvvv