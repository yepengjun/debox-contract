// 2022.11.1  by tiechou

const c = require("./config.json")

const Web3 = require('web3')
const web3 = new Web3(c.network.rpcURL)

function sign_tx(tx, pk) {
    console.log("tx:", tx);
    web3.eth.accounts.signTransaction(tx, pk).then(signed => {
        var tran = web3.eth.sendSignedTransaction(signed.rawTransaction);
        tran.on('confirmation', (confirmationNumber, receipt) => {
            console.log('confirmation: ' + confirmationNumber);
        });
        tran.on('transactionHash', txhash => {
            console.log("txhash: %s/%s", c.network.txPrefix, txhash)
        });
        tran.on('receipt', receipt => {
            console.log('reciept');
            console.log(receipt);
        });
        tran.on('error', console.error);
    });
}

// New Contract Object
const abi = require('./abi.json')
const contract = new web3.eth.Contract(abi, c.network.ca)

// Keccak-256：产生256位哈希，目前由Ethereum使用。
const keccak256 = require('keccak256')
const { MerkleTree } = require('merkletreejs')
const addresses = require('./whitelist.json')

const leaves = addresses.map(x => keccak256(x))
const tree = new MerkleTree(leaves, keccak256, { sortPairs: true })
let proof = tree.getHexProof(keccak256(c.eoa))
console.log("proof:", proof);

// Generate TX
const price = 0;
const num = 1;
const value = (num * price).toString();
const tx = {
    from: c.eoa,
    to: c.network.ca,
    value: web3.utils.toWei(value, 'ether'),
    data: contract.methods.mintAllowList(proof,num).encodeABI()
};

// EstimateGas and Send TX
contract.methods.mintAllowList(proof,num).estimateGas(tx).then(async (gas)=>{
    tx.gas = Number(gas).toFixed();
    sign_tx(tx, c.pk);
}).catch(err=>{
	console.log(err.message);
})
