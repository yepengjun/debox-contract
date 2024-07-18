var abi =require("ethereumjs-abi");
var BN = require("bn.js");

var parameterValues =['0xdc968c02db6b9eda63e53148f278c9b2520f1906','0xA6146598e4D58A1ca49F98591F3A528Fd4c695F9'];
var encoded = abi.rawEncode(['address','address'], parameterValues);
const buf2hex = (x) =>{
  return '0x' + x.toString('hex')
}
console.log(buf2hex(encoded))


var parameterValues =['https://debox.pro/nft/sbt/Qmd1A7kcEJdfbFD7Fx1e7XdquQDAWahTJ4sbDemLvBhoTN/'];
var encoded = abi.rawEncode(['string'], parameterValues);
console.log(buf2hex(encoded))

