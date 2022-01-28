import Vue from 'vue'

import {ethers} from 'ethers'
import WalletConnectProvider from "@walletconnect/web3-provider"

let EthersPlugin = {};

EthersPlugin.install = function (Vue, options) {
    let provider = null;
    let signer = null;
    let blockchain = {};

    const StakeAddress = "0xC240680cCdB710362C582B797cb7AFa0B00911b9";
    const StakeAbi = [
        "function stake(uint16 _item, uint16 _amount) public",
        "function withdraw(uint256[] _stakes) public",
        "function claim(uint256[] _stakes) public",
        "function getStakeIds(address) public view returns (uint[])",
        "function getStakes(address) public view returns (tuple(uint184, uint16, uint24, uint32)[])",
    ];

    const POGAddress = "0x8985420180ACD9320B3808D688240DA23c43f39e";
    const POGAbi = [
        "function balanceOf(address) public view returns (uint256)",
        "function allowance(address, address) public view returns (uint256)",
        "function approve(address spender, uint256 amount) public returns (bool)",
        "function transfer(address to, uint amount)",
    ];

    const NFTAddress = "0xeD275A14023dC979f15fe9493eadfB8045747415";
    const NFTAbi = [
        "function balanceOf(address, uint) public view returns (uint256)",
        "function balanceOfBatch(address[], uint[]) public view returns (uint256[])",
        "function isApprovedForAll(address, address) public view returns (bool)",
        "function setApprovalForAll(address, bool) public",
    ];

    blockchain.ethers = ethers;
    blockchain.getProvider = function(){
        return provider;
    };
    blockchain.setProvider = function(prov){
        provider = new ethers.providers.Web3Provider(prov, "any");
        signer = provider.getSigner();
        return true;
    };
    blockchain.setWalletConnectProvider = async function(){
        let provWC;
        try {
            provWC = new WalletConnectProvider({
                rpc: {56: "https://bsc-dataseed.binance.org"}
            });
            await provWC.enable();
        } catch (e) {
            console.error(e);
            return false;
        }
        provider = new ethers.providers.Web3Provider(provWC, "any");
        signer = provider.getSigner();
        return true;
    };
    blockchain.getSigner = function(){
        if( signer == null )
            signer = provider.getSigner();
        return signer;
    };

    /**
     * @return Promise({boolean})
     */
    blockchain.POGTransfer = async function(accountTo, amountTo) {
        console.log('Send '+ amountTo +' POG to: ', accountTo);
        const POGContract = new ethers.Contract(POGAddress, POGAbi, provider);
        const POGContractSigner = POGContract.connect(signer);
        let amountInt = ethers.utils.parseEther(amountTo.toString());
        try {
            const tx = await POGContractSigner.transfer(accountTo, amountInt);
            const receipt = await tx.wait();
            console.log(receipt);
            return receipt.status === 1;
        } catch (e) {
            console.error(e);
            return false;
        }
    };

    /**
     * @return {string}
     */
    blockchain.POGBalance = async function(account) {
        console.log('Get Balance for: ', account);
        const POGContract = new ethers.Contract(POGAddress, POGAbi, provider);
        let bBal = await POGContract.balanceOf(account);
        return ethers.utils.formatEther(bBal);
    };

    /**
     * @return [NFTApprove, CoinApprove]
     */
    blockchain.NFTBalance = async function(account) {
        console.log('Get NFTs balance for: '+ account);
        const NFTContract = new ethers.Contract(NFTAddress, NFTAbi, provider);
        return await NFTContract.balanceOfBatch([account,account,account,account,account], [5,4,2,3,1]);
    };

    blockchain.CheckApprove = async function(account) {
        console.log('Check Approves for: '+ account);
        let approves = false;
        const POGContract = new ethers.Contract(POGAddress, POGAbi, provider);
        let allowance = await POGContract.allowance(account, StakeAddress);
        if(allowance > 100000000)
            approves = true;
        return approves;
    };

    blockchain.ApproveNFT = async function() {
        console.log('Set approve NFT');
        const NFTContract = new ethers.Contract(NFTAddress, NFTAbi, provider);
        const NFTContractSigner = NFTContract.connect(signer);
        try {
            const tx = await NFTContractSigner.setApprovalForAll(StakeAddress, true);
            const receipt = await tx.wait();
            console.log(receipt);
            return receipt.status === 1;
        } catch (e) {
            console.error(e);
            return false;
        }
    }

    blockchain.ApproveCoin = async function() {
        console.log('Set approve Coin');
        const POGContract = new ethers.Contract(POGAddress, POGAbi, provider);
        const POGContractSigner = POGContract.connect(signer);
        try {
            const tx = await POGContractSigner.approve(StakeAddress, ethers.constants.MaxUint256);
            const receipt = await tx.wait();
            console.log(receipt);
            return receipt.status === 1;
        } catch (e) {
            console.error(e);
            return false;
        }
    }

    blockchain.getStakes = async function(account) {
        console.log('Get my stakes');
        const StakesContract = new ethers.Contract(StakeAddress, StakeAbi, provider);
        const timeNow = Math.floor(+new Date()/1000);
        let staked = {};
        let stakeIDs = await StakesContract.getStakeIds(account);
        if(stakeIDs.length > 0) {
            let stakesData = await StakesContract.getStakes(account);
            for (let i = 0; i < stakeIDs.length; i++) {
                const stake = stakesData[i];

                if(!Array.isArray(staked[stake[0]]))
                    staked[stake[0]] = [];
                staked[stake[0]].push({
                    'stakeId': stakeIDs[i].toString(),
                    'amount': stake[1],
                    'claimed': stake[2],
                    'stakeTime': stake[3],
                    'extraItems': 0
                });
            }
        }
        return staked;

    }

    blockchain.stakePOG = async function(itemID, amount) {
        console.log('Stake for '+ amount +' boxes: ', itemID);
        const POGContract = new ethers.Contract(StakeAddress, StakeAbi, provider);
        const POGContractSigner = POGContract.connect(signer);
        try {
            const tx = await POGContractSigner.stake(itemID, amount);
            const receipt = await tx.wait();
            console.log(receipt);
            return receipt.status === 1;
        } catch (e) {
            console.error(e);
            return false;
        }
    };

    blockchain.claimPOG = async function(itemIDs) {
        console.log('Claim', itemIDs);
        const POGContract = new ethers.Contract(StakeAddress, StakeAbi, provider);
        const POGContractSigner = POGContract.connect(signer);
        try {
            const tx = await POGContractSigner.withdraw(itemIDs);
            const receipt = await tx.wait();
            console.log(receipt);
            return receipt.status === 1;
        } catch (e) {
            console.error(e);
            return false;
        }
    };

    blockchain.claimNFT = async function(itemIDs) {
        console.log('Claim', itemIDs);
        const POGContract = new ethers.Contract(StakeAddress, StakeAbi, provider);
        const POGContractSigner = POGContract.connect(signer);
        try {
            const tx = await POGContractSigner.claim(itemIDs);
            const receipt = await tx.wait();
            console.log(receipt);
            return receipt.status === 1;
        } catch (e) {
            console.error(e);
            return false;
        }
    };

    Vue.prototype.$Web3 = blockchain;
};

Vue.use(EthersPlugin);
