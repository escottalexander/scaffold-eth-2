const contents = () =>
  `# Template for foundry environment variables.

# For local development, copy this file, rename it to .env, and fill in the values.

# We provide default values so developers can start prototyping out of the box,
# but we recommend getting your own API Keys for Production Apps.

# DEPLOYER_PRIVATE_KEY is used while deploying contract.
# On anvil chain the value of it can be empty since we use the prefunded account
# which comes with anvil chain to deploy contract.
# NOTE: You don't need to manually change the value of DEPLOYER_PRIVATE_KEY, it should
# be auto filled when run \`yarn generate\`.
# Although \`.env\` is ignored by git, it's still important that you don't paste your
# actual account private key and use the generated one.
# Alchemy rpc URL is used while deploying the contracts to some testnets/mainnets, checkout \`foundry.toml\` for it's use.
ALCHEMY_API_KEY=oKxs-03sij-U_N0iOlrSsZFr29-IqbuF

# Etherscan API key is used to verify the contract on etherscan.
ETHERSCAN_API_KEY=DNXJA8RX2Q3VZ4URQIWP7Z68CJXQZSC6AW
# Default account for localhost / use "scaffold-eth-custom" if you wish to use a generated account or imported account
ETH_KEYSTORE_ACCOUNT=scaffold-eth-default`;

export default contents;