<template>
    <div class="CaseCard">
        <div>
            <div class="header">{{ caseName }} NFT Box</div>
            <div>Price: {{casePrice}} POG</div><br/>
            <div><b>Boxes in wallet: {{cardData.balance}}</b></div>
            <div><span v-for="num in parseInt(cardData.balance)" style="width: 30px; height: 30px;" :key="num">🎁</span> </div><br/>
            <div>Your current stakes:</div>
            <hr/>
            <div class="stakes-list">
            <div v-for="(stake, index) in myStakes" :key="index">
                <p>Stakes count: {{ stake.amount}}<br/>
                    New box {{ stake.newBoxIn }}<br/>
                    <span v-if="stake.Fee">No Fee {{ stake.noFeeLeft }}</span><br/>
                </p>
                <button @click="$nuxt.$emit('claim-boxes', [stake.stakeId])" :disabled="stake.extraItems===0">Claim {{stake.extraItems}} box{{getPlural(stake.extraItems)}}</button><br/>
                <button @click="$nuxt.$emit('claim-stakes', [stake.stakeId])" :disabled="stake.amountPOG===0">Withdraw <b v-if="stake.Fee">with fee</b>: {{stake.amountPOG}} POG and {{stake.extraItems}} box{{getPlural(stake.extraItems)}}</button><br/>
                <hr/>
            </div>
            </div>
            <button v-if="unlockTokens[0] > 0" @click="$nuxt.$emit('claim-stakes', getClaimableIds())">Withdraw ALL: {{unlockTokens[0]}} POG and {{unlockTokens[1]}} box{{getPlural(unlockTokens[1])}}</button><br/>
        </div>
        <br/>
        <div class="with-button">
            <button @click="$nuxt.$emit('send-allow-transaction')" :disabled="approved" :class="{ 'approved': approved }">Approve</button><br/><br/>
            <div>
                Boxes count: <input class="casesCount" v-model.number="casesToStake" type="number" step="1" min="1" size="3"><br/>
                <button @click="$nuxt.$emit('stake-for-case', [caseId, Math.floor(casesToStake), stakePrice])" :disabled="casesToStake<1 || !approved || stakePrice > parseFloat(pogBalance)">
                    Stake <b>{{stakePrice}}</b> POG and <br/>get {{casesToStake}} <b>{{caseName}} box{{getPlural(casesToStake)}}</b> every 14 days
                </button>
            </div>
        </div>
    </div>
</template>

<script>
export default {
    name: "pogStakeCard",
    props:  ['caseName', 'pogBalance', 'cardData', 'approved'],
    data() {
        return {
            casesToStake: 1,
            timeNow: Math.floor(+new Date()/1000),
        };
    },
    methods: {
        getCost(amount) {
            return amount*this.casePrice;
        },
        getPlural(amount) {
            if(amount === 0) return 'es';
            return (amount > 1)?'es':'';
        },
        getClaimableIds() {
            let stakeIDs = [];
            if(Array.isArray(this.myStakes)) {
                for(let i =0; i < this.myStakes.length; i++) {
                    const stake = this.myStakes[i];
                    if(stake.amountPOG > 0) {
                        stakeIDs.push(stake.stakeId)
                    }
                }
            }
            return stakeIDs;
        },
        getRelativeTime(secondsLeft) {
            const units = {
                year  : 24 * 60 * 60 * 365,
                month : 24 * 60 * 60 * 365/12,
                day   : 24 * 60 * 60,
                hour  : 60 * 60,
                minute: 60,
                second: 1
            }
            const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })
            let timeRel = '';
            for (var u in units)
                if (Math.abs(secondsLeft) > units[u] || u === 'second') {
                    timeRel = rtf.format(Math.round(secondsLeft / units[u]), u);
                    break;
                }
            return timeRel;
        }
    },
    computed: {
        casePrice() {
            // const costs = {
            //     'Bronze': 250,
            //     'Silver': 500,
            //     'Gold': 1000,
            //     'Platinum': 1500,
            //     'Test': 1500,
            // };
            return this.$nuxt.boxesData[this.caseName].price;
        },
        caseId() {
            // const ids = {
            //     'Bronze': '0',
            //     'Silver': '1',
            //     'Gold': '2',
            //     'Platinum': '3',
            //     'Test': '4'
            // };
            return this.$nuxt.boxesData[this.caseName].id.toString();
//            return ids[this.caseName];
        },
        myStakes() {
            console.log('myStakes');
            const feeInfo = this.$nuxt.FeeInfo;
            const stakeTime = this.$nuxt.boxesData[this.caseName].stakeTime;
            let stakes = this.cardData.stakes;
            if(Array.isArray(stakes)) {
                for(let i=0; i < stakes.length; i++) {
                    stakes[i].amountPOG = 0;
                    const stake = stakes[i];
                    let noFeeTimeLeft = (stake.stakeTime + feeInfo.feePeriod) - this.timeNow;
                    let firstBoxTimeLeft = (stake.stakeTime + stakeTime) - this.timeNow;

                    let boxesForTime = 0;
                    if(firstBoxTimeLeft <= 0) {
                        boxesForTime = Math.floor((this.timeNow - stake.stakeTime) / stakeTime);
                    }
                    let newBoxTimeLeft = (stake.stakeTime + stakeTime + stakeTime*boxesForTime) - this.timeNow;
                    stakes[i].newBoxIn = this.getRelativeTime(newBoxTimeLeft);

                    stakes[i].extraItems = boxesForTime * stake.amount - stakes[i].claimed;
                    if(noFeeTimeLeft <= 0) {
                        stakes[i].Fee = false;
                        stakes[i].amountPOG = this.getCost(stake.amount);
                    } else {
                        stakes[i].Fee = true;
                        stakes[i].amountPOG = this.getCost(stake.amount) * feeInfo.feeMult;
                        stakes[i].noFeeLeft = this.getRelativeTime(noFeeTimeLeft);
                    }
                }
                stakes.sort((a,b) => (a.stakeTime > b.stakeTime) ? 1 : ((b.stakeTime > a.stakeTime) ? -1 : 0));
            }
            return stakes;
        },
        stakePrice() {
            return this.casesToStake >= 1? this.getCost(Math.floor(this.casesToStake)): 0;
        },
        unlockTokens() {
            // returns array [POG, ExtraCases]
            let unlock = [0,0];
            if(Array.isArray(this.myStakes)) {
                for(let i =0; i < this.myStakes.length; i++) {
                    const stake = this.myStakes[i];
                    unlock[0] += stake.amountPOG;
                    unlock[1] += stake.extraItems;
                }
            }
            return unlock;
        }
    },
    watch: {
        timeNow: {
            handler(value) {
                setTimeout(() => {
                    this.timeNow = Math.floor(+new Date()/1000);
                }, 10000);
            },
            immediate: true
        }

    }
}
</script>

<style scoped>
.CaseCard {
    margin: 10px;
    padding: 10px;
    min-width: 210px;
    max-width: 250px;
    border: solid 1px gray;
    line-height: 150%;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
}
.CaseCard button {
    padding:7px;
}

.CaseCard .with-button {
    text-align: center;
}
.stakes-list {
    max-height: 310px;
    overflow: auto;
}
.casesCount {
    width: 50px;
}
.CaseCard .approved {
    background-color: palegreen;
}
</style>