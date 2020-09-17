const Migrations = artifacts.require("Migrations")
const Chai = artifacts.require("Chai")
const Controller = artifacts.require("Controller")
const Dai = artifacts.require("Dai")
const DaiJoin = artifacts.require("DaiJoin")
const EDai = artifacts.require("EDai")
const Treasury = artifacts.require("Treasury")
const Vat = artifacts.require("Vat")
const WETH9 = artifacts.require("WETH9")
const GemJoin = artifacts.require("GemJoin")
const Pool = artifacts.require("Pool")
const Pot = artifacts.require("Pot")
const YieldProxy = artifacts.require("YieldProxy")

const ethers = require("ethers")

// Logs all addresses of contracts
module.exports = async (callback) => {
    try {
        migrations = await Migrations.deployed()

        chai = await Chai.at(await migrations.contracts(ethers.utils.formatBytes32String("Chai")))
        controller = await Controller.at(await migrations.contracts(ethers.utils.formatBytes32String("Controller")))
        dai = await Dai.at(await migrations.contracts(ethers.utils.formatBytes32String("Dai")))
        daiJoin = await DaiJoin.at(await migrations.contracts(ethers.utils.formatBytes32String("DaiJoin")))
        // eDai0 = await EDai.at(await migrations.contracts(ethers.utils.formatBytes32String("eDai20Sep")))
        eDai1 = await EDai.at(await migrations.contracts(ethers.utils.formatBytes32String("eDai20Oct")))
        eDai2 = await EDai.at(await migrations.contracts(ethers.utils.formatBytes32String("eDai21Jan")))
        eDai3 = await EDai.at(await migrations.contracts(ethers.utils.formatBytes32String("eDai21Apr")))
        eDai4 = await EDai.at(await migrations.contracts(ethers.utils.formatBytes32String("eDai21Jul")))
        treasury = await Treasury.at(await migrations.contracts(ethers.utils.formatBytes32String("Treasury")))
        vat = await Vat.at(await migrations.contracts(ethers.utils.formatBytes32String("Vat")))
        weth = await WETH9.at(await migrations.contracts(ethers.utils.formatBytes32String("Weth")))
        wethJoin = await GemJoin.at(await migrations.contracts(ethers.utils.formatBytes32String("WethJoin")))
        // pool0 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String("eDaiLP20Sep")))
        pool1 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String("eDaiLP20Oct")))
        pool2 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String("eDaiLP21Jan")))
        pool3 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String("eDaiLP21Apr")))
        pool4 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String("eDaiLP21Jul")))
        pot = await Pot.at(await migrations.contracts(ethers.utils.formatBytes32String("Pot")))
        yieldProxy = await YieldProxy.at(await migrations.contracts(ethers.utils.formatBytes32String("YieldProxy")))
        console.log("Contracts loaded")

        me = "0xF7b3f0F3A6fF862A109ac25464e0Dd3495461386"
        
        RAY = "000000000000000000000000000"
        WAD = "000000000000000000"
        FIN = "000000000000000"
        THOUSAND = "000"
        MILLION = "000000"
        BILLION = "000000000"
        MAX = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        Line = "0x4c696e6500000000000000000000000000000000000000000000000000000000"
        line = "0x6c696e6500000000000000000000000000000000000000000000000000000000"
        spot = "0x73706f7400000000000000000000000000000000000000000000000000000000"
        ETH_A = "0x4554482d41000000000000000000000000000000000000000000000000000000"

        // maturity0 = await eDai0.maturity()
        maturity1 = await eDai1.maturity()
        maturity2 = await eDai2.maturity()
        maturity3 = await eDai3.maturity()
        maturity4 = await eDai4.maturity()

        await vat.hope(daiJoin.address)
        await weth.approve(treasury.address, MAX)
        await weth.approve(wethJoin.address, MAX)
        // await dai.approve(pool0.address, MAX)
        await dai.approve(pool1.address, MAX)
        await dai.approve(pool2.address, MAX)
        await dai.approve(pool3.address, MAX)
        await dai.approve(pool4.address, MAX)
        await dai.approve(yieldProxy.address, MAX)
        // await eDai0.approve(pool0.address, MAX)
        await eDai1.approve(pool1.address, MAX)
        await eDai2.approve(pool2.address, MAX)
        await eDai3.approve(pool3.address, MAX)
        await eDai4.approve(pool4.address, MAX)
        console.log("Approvals granted")
        
        if(!(await controller.delegated(me, yieldProxy.address))) { 
            await controller.addDelegate(yieldProxy.address)
            // await pool0.addDelegate(yieldProxy.address)
            await pool1.addDelegate(yieldProxy.address)
            await pool2.addDelegate(yieldProxy.address)
            await pool3.addDelegate(yieldProxy.address)
            await pool4.addDelegate(yieldProxy.address)
            console.log("Delegates granted")
        }

        rate = (await vat.ilks(ETH_A)).rate
        spot = (await vat.ilks(ETH_A)).spot
                
        await weth.deposit({ value: "600" + WAD })
        console.log("Weth obtained")

        await wethJoin.join(me, "100" + WAD)
        await vat.frob(ETH_A, me, me, me, "100" + WAD, "22000" + WAD)
        await daiJoin.exit(me, "22000" + WAD)
        console.log("Dai obtained")

        await controller.post(ETH_A, me, me, "500" + WAD)

        // await controller.borrow(ETH_A, maturity0, me, me, "30" + MILLION + WAD)
        await controller.borrow(ETH_A, maturity1, me, me, "1" + THOUSAND + WAD)
        await controller.borrow(ETH_A, maturity2, me, me, "1" + THOUSAND + WAD)
        await controller.borrow(ETH_A, maturity3, me, me, "1" + THOUSAND + WAD)
        await controller.borrow(ETH_A, maturity4, me, me, "1" + THOUSAND + WAD)
        console.log("eDai obtained")

        // await pool0.init("1" + MILLION + WAD)
        await pool1.init("1" + THOUSAND + WAD)
        await pool2.init("1" + THOUSAND + WAD)
        await pool3.init("1" + THOUSAND + WAD)
        await pool4.init("1" + THOUSAND + WAD)
        console.log("Pools initialized")
                
        // await yieldProxy.addLiquidity(pool0.address, "1" + MILLION + WAD, "2" + MILLION + WAD)
        await yieldProxy.addLiquidity(pool1.address, "1" + THOUSAND + WAD, MAX)
        await yieldProxy.addLiquidity(pool2.address, "1" + THOUSAND + WAD, MAX)
        await yieldProxy.addLiquidity(pool3.address, "1" + THOUSAND + WAD, MAX)
        await yieldProxy.addLiquidity(pool4.address, "1" + THOUSAND + WAD, MAX)
        console.log("Liquidity added")

        // await yieldProxy.sellEDai(pool0.address, me, "250" + THOUSAND + WAD, "125" + THOUSAND + WAD)
        await yieldProxy.sellEDai(pool1.address, me, "250" + WAD, 0)
        await yieldProxy.sellEDai(pool2.address, me, "250" + WAD, 0)
        await yieldProxy.sellEDai(pool3.address, me, "250" + WAD, 0)
        await yieldProxy.sellEDai(pool4.address, me, "250" + WAD, 0)
        console.log("eDai sold")

        callback()
    } catch (e) {console.log(e)}
}