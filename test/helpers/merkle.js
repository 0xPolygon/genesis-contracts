const AbiCoder = require('web3-eth-abi')
const { keccak256 } = require('web3-utils')

const abi = AbiCoder

class SparseMerkleTree {
  constructor(height) {
    if (height <= 1) {
      throw new Error('invalid height, must be greater than 1')
    }
    this.height = height
    this.zeroHashes = this.generateZeroHashes(height)
    const tree = []
    for (let i = 0; i <= height; i++) {
      tree.push([])
    }
    this.tree = tree
    this.leafCount = 0
    this.dirty = false
  }

  add(leaf) {
    this.dirty = true
    this.leafCount++
    this.tree[0].push(leaf)
  }

  calcBranches() {
    for (let i = 0; i < this.height; i++) {
      const parent = this.tree[i + 1]
      const child = this.tree[i]
      for (let j = 0; j < child.length; j += 2) {
        const leftNode = child[j]
        const rightNode =
          j + 1 < child.length ? child[j + 1] : this.zeroHashes[i]
        parent[j / 2] = keccak256(
          abi.encodeParameters(['bytes32', 'bytes32'], [leftNode, rightNode])
        )
      }
    }
    this.dirty = false
  }

  getProofTreeByIndex(index) {
    if (this.dirty) this.calcBranches()
    const proof = []
    let currentIndex = index
    for (let i = 0; i < this.height; i++) {
      currentIndex =
        currentIndex % 2 === 1 ? currentIndex - 1 : currentIndex + 1
      if (currentIndex < this.tree[i].length)
        proof.push(this.tree[i][currentIndex])
      else proof.push(this.zeroHashes[i])
      currentIndex = Math.floor(currentIndex / 2)
    }

    return proof
  }

  getProofTreeByValue(value) {
    const index = this.tree[0].indexOf(value)
    if (index === -1) throw new Error('value not found')
    return this.getProofTreeByIndex(index)
  }

  getRoot() {
    if (this.tree[0][0] === undefined) {
      // No leafs in the tree, calculate root with all leafs to 0
      return keccak256(
        abi.encodeParameters(
          ['bytes32', 'bytes32'],
          [this.zeroHashes[this.height - 1], this.zeroHashes[this.height - 1]]
        )
      )
    }
    if (this.dirty) this.calcBranches()

    return this.tree[this.height][0]
  }

  generateZeroHashes(height) {
    // keccak256(abi.encode(uint256(0), address(0), new bytes(0)));
    const zeroHashes = [
      keccak256(
        abi.encodeParameters(
          ['uint256', 'address', 'bytes'],
          [0, '0x' + '0'.repeat(40), '0x']
        )
      )
    ]
    for (let i = 1; i < height; i++) {
      zeroHashes.push(
        keccak256(
          abi.encodeParameters(
            ['bytes32', 'bytes32'],
            [zeroHashes[i - 1], zeroHashes[i - 1]]
          )
        )
      )
    }

    return zeroHashes
  }
}

function getLeaf(stateID, receiverAddress, stateData) {
  return keccak256(
    abi.encodeParameters(
      ['uint256', 'address', 'bytes'],
      [stateID, receiverAddress, stateData]
    )
  )
}

const [receiver, stateDatasEncoded] = process.argv.slice(2)

const stateDatas = abi.decodeParameter('bytes[]', stateDatasEncoded)

const tree = new SparseMerkleTree(16)

for (let i = 0; i < stateDatas.length; i++) {
  tree.add(getLeaf(i + 1, receiver, stateDatas[i]))
}
const root = tree.getRoot()
const proofs = stateDatas.map((_, i) => tree.getProofTreeByIndex(i))

console.log(
  abi.encodeParameters(
    ['bytes32', 'bytes[]'],
    [root, proofs.map((proof) => abi.encodeParameter('bytes32[16]', proof))]
  )
)
