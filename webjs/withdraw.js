// 2022.11.1  by tiechou

const c = require("./goerli.config.json")

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

// Generate TX
const tx = {
    from: c.eoa,
    to: c.network.ca,
    data: contract.methods.withdraw().encodeABI()
};

// EstimateGas and Send TX
contract.methods.withdraw().estimateGas(tx).then(async (gas)=>{
    tx.gas = Number(gas).toFixed();
    sign_tx(tx, c.pk);
}).catch(err=>{
	console.log(err.message);
})
