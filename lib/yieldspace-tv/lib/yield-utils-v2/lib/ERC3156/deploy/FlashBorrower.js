const func = async function ({ deployments, getNamedAccounts, getChainId }) {
    const { deploy, read, execute } = deployments
    const { deployer } = await getNamedAccounts()
    const chainId = await getChainId()

    const borrower = await deploy('FlashBorrower', {
        from: deployer,
        deterministicDeployment: true,
    })
    console.log(`Deployed FlashBorrower to ${borrower.address}`)
}

module.exports = func
module.exports.tags = ["FlashBorrower"]