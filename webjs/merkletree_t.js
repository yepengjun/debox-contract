// Keccak-256：产生256位哈希，目前由Ethereum使用。
const keccak256 = require('keccak256')
const { MerkleTree } = require('merkletreejs')

const addresses = ["0x42792048c8519e2B0e66B448543a53B88626D0Ea","0x7f4B248427B845B70F7c1c81830463835D56e32f","0xf2Ff98000Cc0700A640274db8d492f2DdF6929Fa","0x1eC1C16957745cdC224FD852AAFdD133f3897078","0xb719Fc59e5019DA292E6FaD7781c05B078585278","0xaf35680c243ab73bf90d3704688c6038f127f3b0","0xB8662e2A6019698B04FA4048c390c68EBeA2b2C1"]
// 通过hash生成叶子，返回二进制格式（buffer）
const leaves = addresses.map(x => keccak256(x))

// MerkleTree 运算
const tree = new MerkleTree(leaves, keccak256, { sortPairs: true })

// 获取 root
const root = tree.getHexRoot()
console.log('\n-------------------root-----------------')
console.log(root);

let leaf = '0x1eC1C16957745cdC224FD852AAFdD133f3897078'
console.log('\n-------------------leaf-----------------')
console.log(leaf);
console.log(keccak256(leaf));

// 获取到 proof
let proof = tree.getHexProof(keccak256(leaf))
console.log('\n-------------------proof-----------------')
console.log(proof);

const verify = tree.verify(proof,keccak256(leaf),tree.getRoot());
console.log(verify);

// buffer 转换成 16进制
const buf2hex = (x) =>{
  return '0x' + x.toString('hex')
}
// buffer 转换成 16进制，在合约 isValid 验证白名单
let inputRemixLeaf = buf2hex(keccak256(addresses[0]))
