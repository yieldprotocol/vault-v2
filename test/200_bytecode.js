const Vat = artifacts.require('Vat');
const Pot = artifacts.require('Pot');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');
const Chai = artifacts.require('Chai');
const ERC20 = artifacts.require('TestERC20');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Mint = artifacts.require('Mint');
const WethOracle = artifacts.require('WethOracle');
const WethDealer = artifacts.require('WethDealer');
const ChaiOracle = artifacts.require('ChaiOracle');
const ChaiDealer = artifacts.require('ChaiDealer');

const truffleAssert = require('truffle-assertions');

contract('Gas', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let pot;
    let treasury;
    let yDai;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let chai;
    let mint;
    let wethOracle;
    let wethDealer;
    let chaiOracle;
    let chaiDealer;
    let maturity;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const RAD = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    const spot  = "1500000000000000000000000000";
    const rate  = "1250000000000000000000000000";
    const price  = "1200000000000000000000000000"; // spot / rate
    const daiTokens = web3.utils.toWei("125");  // Dai we borrow
    const daiDebt = web3.utils.toWei("100");    // Dai debt for `frob`: daiTokens / rate = 100
    const wethTokens = web3.utils.toWei("150"); // Collateral we join: daiTokens * price = 125


    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.rely(vat.address, { from: owner });

        weth = await ERC20.new(0, { from: owner }); 
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?
        const rateIncrease  = "250000000000000000000000000";
        await vat.fold(ilk, vat.address, rateIncrease, { from: owner }); // 1 + 0.25

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Set treasury
        treasury = await Treasury.new(
            dai.address,        // dai
            chai.address,       // chai
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup mint
        mint = await Mint.new(
            treasury.address,
            dai.address,
            yDai.address,
            { from: owner },
        );
        await yDai.grantAccess(mint.address, { from: owner });
        await treasury.grantAccess(mint.address, { from: owner });

        // Setup ChaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Setup ChaiDealer
        chaiDealer = await ChaiDealer.new(
            treasury.address,
            dai.address,
            yDai.address,
            chai.address,
            chaiOracle.address,
            { from: owner },
        );
        await yDai.grantAccess(chaiDealer.address, { from: owner });
        await treasury.grantAccess(chaiDealer.address, { from: owner });

        // Setup WethOracle
        wethOracle = await WethOracle.new(vat.address, { from: owner });

        // Setup WethDealer
        wethDealer = await WethDealer.new(
            treasury.address,
            dai.address,
            yDai.address,
            weth.address,
            wethOracle.address,
            { from: owner },
        );
        await yDai.grantAccess(wethDealer.address, { from: owner });
        await treasury.grantAccess(wethDealer.address, { from: owner });
    });

    it("get the size of the contract", async() => {
        const contracts = [treasury, mint, chaiDealer, wethDealer];
        console.log("-----------------------------------------------------");
        console.log("|    Contract|    Bytecode|    Deployed| Constructor|");
        console.log("-----------------------------------------------------");
        
        contracts.forEach(contract => {
            const bytecode = contract.constructor._json.bytecode;
            const deployed = contract.constructor._json.deployedBytecode;
            const sizeOfB  = bytecode.length / 2;
            const sizeOfD  = deployed.length / 2;
            const sizeOfC  = sizeOfB - sizeOfD;
            console.log(
                "|" + (contract.constructor._json.contractName).padStart(12, ' ') +
                "|" + ("" + sizeOfB).padStart(12, ' ') +
                "|" + ("" + sizeOfD).padStart(12, ' ') +
                "|" + ("" + sizeOfC).padStart(12, ' ') + "|");
        })
        console.log("-----------------------------------------------------");
    });
});