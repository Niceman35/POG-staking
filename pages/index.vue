<template>
      <div>
          <div>
              <div class="connectClass">
                  <div v-if="myWallet">My Wallet: {{ myWallet }}</div>
                  <div><button class="buttonConnect"
                               :class="{ active: MetamaskActive }"
                               @click="connectMatamask">Connect Metamask(Web3)</button></div>
                  <div><button class="buttonConnect walletConnect"
                               :class="{ active: WalletConnectActive }"
                               @click="WalletConnect"></button></div>
              </div>
          </div>
          <div>My POG balance: <b>{{ pogData.pogBalance }}</b></div>
          <div class="casesCards">
              <pog-stake-card v-for="boxData in $nuxt.boxesData" :case-name="boxData.name"
                              :pog-balance="pogData.pogBalance"
                              :card-data="pogData[boxData.name.toLowerCase()]"
                              :approved="pogData.approvedCoin"></pog-stake-card>
          </div>
      </div>
</template>

<script>
export default {
    data() {
        return {
            myWallet: '',
            MetamaskActive: false,
            WalletConnectActive: false,
            pogData: {
                approvedCoin: false,
                pogBalance:'0.0',
                bronze: {balance: '0', stakes: {}},
                silver: {balance: '0', stakes: {}},
                gold: {balance: '0', stakes: {}},
                platinum: {balance: '0', stakes: {}},
                test: {balance: '0', stakes: {}},
            },
        };
    },
    computed: {
    },
    methods: {
        getBalance() {
            console.log('Load POG balance');
            if(this.myWallet > '') {
                this.$Web3.POGBalance(this.myWallet).then(balance => {
                    this.pogData.pogBalance = balance;
                })
            } else {
                this.pogData.pogBalance = '0.00';
            }
        },
        getBoxes() {
            console.log('Load NFT balances');
            if(this.myWallet > '') {
                this.$Web3.NFTBalance(this.myWallet).then(balance => {
                    for (const stakeName in this.$nuxt.boxesData) {
                        const stakeInfo = this.$nuxt.boxesData[stakeName]
                        this.pogData[stakeInfo.name.toLowerCase()].balance = balance[stakeInfo.id].toString();
                    }
                });
            }
        },
        getAllowance() {
            console.log('Check allowance');
            if(this.myWallet > '') {
                this.$Web3.CheckApprove(this.myWallet).then(allowance => {
                    this.pogData.approvedCoin = allowance;
                });
            }
        },
        async getStakes() {
            console.log('getStakes');
            if(this.myWallet > '') {
                this.$Web3.getStakes(this.myWallet).then(stakes => {
                    for (const stakeName in this.$nuxt.boxesData) {
                        const stakeInfo = this.$nuxt.boxesData[stakeName]
                        this.pogData[stakeInfo.name.toLowerCase()].stakes = stakes[stakeInfo.id] || [];
                    }
                })
            }
        },
        async sendAllow() {
            console.log('sendAllow');
            if(!this.pogData.approvedCoin) {
                let status = await this.$Web3.ApproveCoin();
                if(status)
                    this.pogData.approvedCoin = true;
            }
        },
        async stakePog(params) {
            console.log('StakeBox');
            const boxID = params[0];
            const boxCount = params[1];

            if(this.pogData.pogBalance < params[3]) {alert('You do not have enough POG balance. '+params[3]+' POG needed'); return;}
            if(!this.pogData.approvedCoin) {alert('You do not approved POG transfers'); return;}
            let status = await this.$Web3.stakePOG(boxID, boxCount);
            if(status) {
                alert('Stake successful.');
                await this.getBalance();
                await this.getBoxes();
                await this.getStakes();
            } else {
                alert('Error: Transaction not confirmed.');
            }
        },
        async claimPog(stakeIDs) {
            console.log('WithdrawPOG');
            console.log(stakeIDs);
            let status = await this.$Web3.claimPOG(stakeIDs);
            if(status) {
                alert('Claimed successful.');
                await this.getBalance();
                await this.getBoxes();
                await this.getStakes();
            } else {
                alert('Error: Transaction not confirmed.');
            }
        },
        async claimNFT(stakeIDs) {
            console.log('Claim Box');
            console.log(stakeIDs);
            let status = await this.$Web3.claimNFT(stakeIDs);
            if(status) {
                alert('Claimed successful.');
                await this.getBalance();
                await this.getBoxes();
                await this.getStakes();
            } else {
                alert('Error: Transaction not confirmed.');
            }
        },
        async connectMatamask() {
            if (window.ethereum) {
                this.$Web3.setProvider(window.ethereum);
                try {
                    let accounts = await this.$Web3.getProvider().send("eth_requestAccounts");
                    console.log(accounts);
                    this.myWallet = await this.$Web3.getSigner().getAddress();
                    this.MetamaskActive = true;
//                    this.myWallet = accounts[0];
                    return true;
                } catch (error) {
                    this.MetamaskActive = false;
                    console.log(error);
                    return false;
                }
            }
        },
        async WalletConnect() {
            let status = await this.$Web3.setWalletConnectProvider();
            if(status) {
                let provider = await this.$Web3.getProvider();
                this.myWallet = provider.provider.accounts[0];
                provider.provider.on("disconnect", (error, payload) => {
                    console.log("WalletConnect disconnected: ", payload);
                    this.WalletConnectActive = false;
                    this.myWallet = '';
                });
                this.WalletConnectActive = true;
            } else {
                this.WalletConnectActive = false;
                this.myWallet = '';
            }
        },
        async isMetamaskConnected() {
            if (window.ethereum) {
                this.$Web3.setProvider(window.ethereum);
                let network = await this.$Web3.getProvider().getNetwork();
                console.log(network.chainId);
                if(network.chainId === 97) { //97 - testnet  56 - mainnet
                    try {
                        this.myWallet = await this.$Web3.getSigner().getAddress();
                        this.MetamaskActive = true;
//                         await this.$Web3.getProvider().send("eth_requestAccounts");
                        return true;
                    } catch (error) {
                        this.MetamaskActive = false;
                        console.log(error);
                        return false;
                    }
                } else {
                    alert('Wrong network. Switch to the Binance Smart Chain');
                }
            }
        }
    },
    watch: {
        myWallet(newWallet, oldWallet) {
            console.log('Watcher myWallet');
            console.log(newWallet);
            if(newWallet > '') {
                this.getBalance();
                this.getBoxes();
                this.getAllowance();
                this.getStakes();
            } else {
                this.pogData.pogBalance = '0.00';
            }
        }
    },
    created() {
        this.$nuxt.$on('send-allow-transaction', () => {
            this.sendAllow();
        });
        this.$nuxt.$on('stake-for-case', (params) => {
            this.stakePog(params);
        });
        this.$nuxt.$on('claim-stakes', (params) => {
            this.claimPog(params);
        });
        this.$nuxt.$on('claim-boxes', (params) => {
            this.claimNFT(params);
        });
        this.$nuxt.boxesData = {
            'Bronze' : {id: 0, name: "Bronze", price: 250, stakeTime: 1209600, nftID: '5'},
            'Silver' : {id: 1, name: "Silver", price: 500, stakeTime: 1209600, nftID: '4'},
            'Gold' : {id: 2, name: "Gold", price: 1000, stakeTime: 1209600, nftID: '2'},
            'Platinum' : {id: 3, name: "Platinum", price: 1500, stakeTime: 1209600, nftID: '3'},
            'Test' : {id: 4, name: "Test", price: 1500, stakeTime: 300, nftID: '1'},
        }
        this.$nuxt.FeeInfo = {feeMult: 0.98, feePeriod: 86400}

    },
    beforeDestroy(){
        this.$nuxt.$off('send-allow-transaction');
        this.$nuxt.$off('stake-for-case');
        this.$nuxt.$off('claim-stakes');
    },
    async mounted() {
        if(await this.isMetamaskConnected()) {
            console.log('My Wallet ', this.myWallet);
            if (typeof window.ethereum !== "undefined") {
                window.ethereum.on('accountsChanged', (accounts) => {
                    this.myWallet = accounts[0];
                });
            }

        } else {
//            alert('Can not connect to Metamask wallet');
        }
    }
}
</script>

<style>
body {
    line-height: 150%;
}
.casesCards {
    display: flex;
}
.buttonConnect {
    padding: 8px;
    height: 40px;
}
.buttonConnect.walletConnect {
    background: #f0f0f0 url("~/assets/walletConnect.svg") no-repeat 0 -32px;
    background-size: 150px;
    width: 155px;
}
.buttonConnect.active {
    background-color: #cff0cf;
}
.connectClass {
    display: flex;
    justify-content: space-between;
}

</style>