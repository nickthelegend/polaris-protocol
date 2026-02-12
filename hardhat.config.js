require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [
            { version: "0.8.20", settings: { viaIR: true, optimizer: { enabled: true, runs: 200 } } },
            { version: "0.8.23", settings: { viaIR: true, optimizer: { enabled: true, runs: 200 } } }
        ],
    },
    networks: {
        hardhat: {
            chainId: 1337,
        },
        ganache: {
            url: "http://127.0.0.1:7545",
            accounts: ["0xdb8cfa2db2a866e6fea3d4388da2278f8ef7367180d5921b96661d946b244c86"],
        },
        ctcTestnet: {
            url: "https://rpc.cc3-testnet.creditcoin.network",
            chainId: 102031,
            accounts: ["0xc1c46d8f06533e4aa0899a933ee5ba8556b244b7f262cf1b4702c575257956a2"],
        },
        uscTestnet: {
            url: "https://rpc.usc-testnet.creditcoin.network",
            chainId: 102033,
            accounts: ["0xc1c46d8f06533e4aa0899a933ee5ba8556b244b7f262cf1b4702c575257956a2"],
        },
        sepolia: {
            url: "https://1rpc.io/sepolia",
            accounts: ["0xc1c46d8f06533e4aa0899a933ee5ba8556b244b7f262cf1b4702c575257956a2"],
        },
        baseSepolia: {
            url: "https://sepolia.base.org",
            accounts: ["0xc1c46d8f06533e4aa0899a933ee5ba8556b244b7f262cf1b4702c575257956a2"],
            chainId: 84532
        },
        uscTestnetV2: {
            url: "https://rpc.usc-testnet2.creditcoin.network",
            chainId: 102036,
            accounts: ["0xc1c46d8f06533e4aa0899a933ee5ba8556b244b7f262cf1b4702c575257956a2"],
        },
        hederaTestnet: {
            url: "https://testnet.hashio.io/api",
            chainId: 296,
            accounts: ["0xc1c46d8f06533e4aa0899a933ee5ba8556b244b7f262cf1b4702c575257956a2"],
        }
    }
};
