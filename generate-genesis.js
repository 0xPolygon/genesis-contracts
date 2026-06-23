const { spawn } = require("child_process")
const program = require("commander")
const nunjucks = require("nunjucks")
const fs = require("fs")
const web3 = require("web3")

const validators = require("./validators")
const blocks = require("./blocks");
const sprintSizes = require("./sprintSizes");

// load and execute bor validator set
require("./generate-borvalidatorset")

program.version("0.0.1")
program.option("-c, --bor-chain-id <bor-chain-id>", "Bor chain id", "15001")
program.option(
  "-o, --output <output-file>",
  "Genesis json file",
  "./genesis.json"
)
program.option(
  "-t, --template <template>",
  "Genesis template json",
  "./genesis-template.json"
)
program.option(
  "--reserved-block <reserved-block>",
  "Reserved-blockspace fork activation block. Omit to leave the fork unscheduled (mainnet/amoy default); set on devnets only."
)
program.option(
  "--reserved-clients <reserved-clients>",
  "Devnet test stub for the reserved client set, e.g. '[{\"addresses\":[\"0x..\"],\"quotaGas\":30000000}]'. " +
    "This is NOT the registry contract schema (POS-3572) — it carries only addresses + per-block quotaGas, " +
    "the minimum to test classification and (once POS-3575 lands) quota enforcement. feeMode/effectiveFrom/" +
    "clientId/ceilingGas are out of scope here. Listed addresses are also funded in the genesis alloc."
)
program.parse(process.argv)

// compile contract
async function compileContract(key, contractFile, contractName, solcVersion) {
  return new Promise((resolve, reject) => {
    const ls = spawn(
      `solc-select use ${solcVersion} && solc --bin-runtime openzeppelin-solidity/=node_modules/openzeppelin-solidity/ /=/ ${contractFile}`,
      { shell: true }
    )

    const result = []
    ls.stdout.on("data", data => {
      result.push(data.toString())
    })

    ls.stderr.on("data", data => {
      result.push(data.toString())
    })

    ls.on("close", code => {
      console.log(`child process exited with code ${code}`)
      const fn = code === 0 ? resolve : reject
      fn(result.join(""))
    })
  }).then(compiledData => {
    compiledData = compiledData.replace(
      new RegExp(`======= ${contractFile}:${contractName} =======\nBinary of the runtime part:` + '[ ]?'),
      "@@@@"
    )

    const matched = compiledData.match(/@@@@\n([a-f0-9]+)/)
    return { key, compiledData: matched[1], contractName, contractFile }
  })
}

// parseReservedInputs validates and normalizes the devnet reserved-blockspace
// flags. Returns falsy defaults when neither flag is set (mainnet/amoy renders
// stay byte-identical). Fails loud on malformed input instead of writing a
// broken genesis. reservedBlock stays a string so "0" remains truthy and can
// schedule the fork at genesis — do not numerically coerce it.
function parseReservedInputs(blockArg, clientsArg) {
  if (blockArg == null && clientsArg == null) {
    return { reservedBlock: null, reservedClients: [] }
  }
  if (blockArg == null || clientsArg == null) {
    throw new Error("--reserved-block and --reserved-clients must be provided together")
  }
  if (!/^\d+$/.test(String(blockArg))) {
    throw new Error(`--reserved-block must be a non-negative integer, got: ${blockArg}`)
  }

  let clients
  try {
    clients = JSON.parse(clientsArg)
  } catch (e) {
    throw new Error(`--reserved-clients is not valid JSON: ${e.message}`)
  }
  if (!Array.isArray(clients)) {
    throw new Error("--reserved-clients must be a JSON array")
  }
  for (const c of clients) {
    if (!c || !Array.isArray(c.addresses) || c.addresses.length === 0) {
      throw new Error("each reserved client must have a non-empty 'addresses' array")
    }
    for (const a of c.addresses) {
      if (!/^0x[0-9a-fA-F]{40}$/.test(a)) {
        throw new Error(`invalid reserved client address: ${a}`)
      }
    }
    if (!Number.isInteger(c.quotaGas) || c.quotaGas < 0) {
      throw new Error(`reserved client quotaGas must be a non-negative integer, got: ${c.quotaGas}`)
    }
  }
  return { reservedBlock: String(blockArg), reservedClients: clients }
}

// compile files sequentially
async function main() {
  const result = []
  for (const file of [
    [
      "borValidatorSetContract",
      "contracts/BorValidatorSet.sol",
      "BorValidatorSet",
      "0.5.17"
    ],
    [
      "borStateReceiverContract",
      "contracts/StateReceiver.sol",
      "StateReceiver",
      "0.6.12"
    ],
    [
      "maticChildERC20Contract",
      "matic-contracts/contracts/child/MRC20.sol",
      "MRC20",
      "0.5.17"
    ]
  ]) {
    result.push(await compileContract(...file))
  }
  const totalMaticSupply = web3.utils.toBN('10000000000')

  var validatorsBalance = web3.utils.toBN(0)
  validators.forEach(v => {
    validatorsBalance = validatorsBalance.add(web3.utils.toBN(v.balance))
    v.balance = web3.utils.toHex(web3.utils.toWei(String(v.balance)))
  })

  const contractBalance = totalMaticSupply.sub(validatorsBalance)
  const data = {
    chainId: program.borChainId,
    validators: validators,
    maticChildERC20ContractBalance: web3.utils.toHex(
      web3.utils.toWei(contractBalance.toString())
    ),
    blocks: blocks,
    sprintSizes: sprintSizes,
    // Reserved-blockspace fork inputs. Both stay falsy unless the caller passes
    // the devnet flags, so mainnet/amoy genesis renders are unchanged.
    ...parseReservedInputs(program.reservedBlock, program.reservedClients)
  }

  result.forEach(r => {
    data[r.key] = r.compiledData
  })

  const templateString = fs.readFileSync(program.template).toString()
  const resultString = nunjucks.renderString(templateString, data)
  fs.writeFileSync(program.output, resultString)
}

main().catch(err => {
  console.log(err)
  process.exit(1)
})
