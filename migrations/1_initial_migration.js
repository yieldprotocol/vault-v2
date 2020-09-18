const { callbackify } = require('util')

const fs = require('fs')

const Migrations = artifacts.require('Migrations')

module.exports = function (deployer) {
  let commit = 'Unknown'
  try {
    const branch = fs.readFileSync('.git/HEAD').toString().replace('ref: ', '').trim()
    commit = fs.readFileSync(`.git/${branch}`).toString().trim()
  } catch (error) {
    console.log('Commit not found')
  }
  deployer.deploy(Migrations, commit)
}
