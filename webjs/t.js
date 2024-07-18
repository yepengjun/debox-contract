// 2022.11.1  by tiechou

const c = require("./config.json")
console.log("-----------------------------------------");
console.log("config:", c)

const Web3 = require('web3')
const web3 = new Web3(c.network.rpcURL)

console.log("-----------------------------------------");
console.log("fromWei:", web3.utils.fromWei("123456789123456789", "ether"))
console.log("toWei:", web3.utils.toWei("0.123456789123456789", "ether"))

// Data Sign and Recover
tc = web3.eth.accounts.sign(c.name + new Date().getTime(), c.pk);
console.log("-----------------------------------------");
console.log("sign:", tc);
console.log("recover sign:", web3.eth.accounts.recover(tc.message, tc.signature));

 
console.log("-----------------------------------------");
web3.eth.getBalance(c.eoa, (err, wei) => {
    balance = web3.utils.fromWei(wei, 'ether')
    console.log("balance wei:", wei)
    console.log("balance:", balance)
})

function nft_mint(gas) {
    console.log("realtime gas:", gas);
    contract.methods.mint(1).send({from:c.eoa, value:web3.utils.toWei('0.1','ether'), gas:gas }, function(err, txhash){
        console.log("f=>", err);
        if (!err) {
            console.log("tx hash: https://etherscan.io/tx/", txhash)
        }
    }).then((res)=>{
        console.log("t=>", res);
        let obj = JSON.stringify(res.events);
        var jsObject = JSON.parse(obj);
        data.nftform.returnId = jsObject['Transfer']['returnValues']['tokenId'];					
    }).catch((err)=>{
        console.log("c=>", err.message);
    });
}
    

// New Contract Object
const abi = require('./abi.json')
const contract = new web3.eth.Contract(abi, c.network.ca)

// Call Contract Methods
console.log("-----------------------------------------");
contract.methods.name().call((err, result) => { 
    console.log("name:", result) 
})
contract.methods.balanceOf(c.eoa).call((err, result) => { 
    console.log("balance:", result) 
})

