const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Migrations = artifacts.require("Migrations");

module.exports = async (callback) => {

    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;

    let ilk = web3.utils.fromAscii("WETH")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('49')
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    const spot  = "1500000000000000000000000000";
    const rate  = "1250000000000000000000000000";
    const daiDebt = web3.utils.toWei("120");    // Dai debt for `frob`: 120
    const wethTokens = web3.utils.toWei("100"); // Collateral we join: 120 * rate / spot
    const daiTokens = web3.utils.toWei("150");  // Dai we can borrow: 120 * rate

    try {
        console.log('Setup Execution started...')

        // get deployed contracts
        vat = await Vat.deployed();
        migrations = await Migrations.deployed();
        weth =  await migrations.contracts('weth');
        dai = await migrations.contracts('chai');
        wethJoin = await GemJoin.deployed();
        daiJoin = await DaiJoin.deployed();

        // run operations
        await vat.init(ilk);
        await vat.file(ilk, spotName, spot );
        await vat.file(ilk, linel, limits );
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(vat.address );      // `owner` authorizing `vat` to operate for `vat`?
        await vat.rely(wethJoin.address ); // `owner` authorizing `wethJoin` to operate for `vat`
        await vat.rely(daiJoin.address );  // `owner` authorizing `daiJoin` to operate for `vat`
        await vat.hope(daiJoin.address ); // `owner` allowing daiJoin to move his dai.

        const rateIncrease  = "250000000000000000000000000";
        await vat.fold(ilk, vat.address, rateIncrease ); // 1 + 0.25

        console.log('executed successfully')

    } 
    catch (e) {console.log(e)}
}
