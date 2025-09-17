const ethUtils = require("ethereumjs-util");
const crypto = require("crypto");
const ethers = require("ethers");

const abi = new ethers.AbiCoder();

function getRandomInt() {
  return Math.floor(Math.random() * 100);
}

// INPUT HOW MANY TO GENERATE

const numOfValidators = process.argv[2];
const numOfProducers = process.argv[3];
const specificSigners =
  process.argv[4] == undefined
    ? undefined
    : abi.decode(["address[]"], process.argv[4])[0];
if (numOfProducers > numOfValidators) process.exit(1);
if (specificSigners != undefined && specificSigners.length != numOfValidators)
  process.exit(1);

// RANDOMLY GENERATED

function getRandomValidator() {
  return [
    getRandomInt(), // id
    getRandomInt(), // power
    "0x" + crypto.randomBytes(20).toString("hex"), // signer
  ];
}

let totalStake = 0;

const ids = new Array(numOfValidators);
const powers = new Array(numOfValidators);
const signers = new Array(numOfValidators);

const validators = new Array(numOfValidators);
for (let i = 0; i < numOfValidators; i++) {
  validators[i] = getRandomValidator();
  totalStake += validators[i].power;

  ids[i] = validators[i][0];
  powers[i] = validators[i][1];
  if (specificSigners != undefined) validators[i][2] = specificSigners[i];
  signers[i] = validators[i][2];
}
this.producers = validators.slice(0, numOfProducers);
const validatorBytes = ethUtils.bufferToHex(ethUtils.rlp.encode(validators));
const producerBytes = ethUtils.bufferToHex(ethUtils.rlp.encode(this.producers));

// THIS WILL BE RETURNED

const result = abi.encode(
  ["uint256[]", "uint256[]", "address[]", "bytes", "bytes"],
  [ids, powers, signers, validatorBytes, producerBytes]
);

console.log(result);
