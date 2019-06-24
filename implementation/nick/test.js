const Web3 = require('web3')

let web3 = new Web3('http://localhost:8545')

const abi = require('./outputDirectory/Contract.abi.json')
console.log(abi)
const contract = new web3.eth.Contract(abi, '0x94ed021657c054ccb767cc448b59a65e732d2bd8')

contract.methods.returnBytes.call().then(x => {
    console.log(x)
})