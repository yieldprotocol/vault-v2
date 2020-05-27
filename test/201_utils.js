const { toRay, toRad, toRay2, toRad2 } = require("./shared/utils")

contract('Test', async (accounts) =>  {
    const spot  =  "1500000000000000000000000000";
    const rate  =  "1250000000000000000000000000";
    const price  = "1200000000000000000000000000"; // spot / rate
    const limits = "1000000000000000000000000000000000000000000000";
    const frac =   "1500000000000000000000000000000000000000000000";

    describe("toRay", async() => {
        it("runs toRay", async() => {
            assert(
                toRay(5).toString() ==
                "5000000000000000000000000000",
                "toRay not working"
            )
        });    
    
        it("handles decimals", async() => {
            assert(
                toRay(1.5).toString() ==
                spot,
                "toRay failing with decimals"
            );
            assert(
                toRay("1.5").toString() ==
                spot,
                "toRay failing with decimals"
            );
            assert(
                toRay("1.25").toString() ==
                rate,
                "toRay failing with decimals"
            );
            assert(
                toRay("1.2").toString() ==
                price,
                "toRay failing with decimals"
            );
        });    
    })

    describe("toRad", async() => {
        it("runs toRad", async() => {
            assert(
                toRad(1).toString() ==
                limits,
                "toRad not working"
            )
        });    
    
        it("handles decimals", async() => {
            assert(
                toRad("1.5").toString() ==
                frac,
                "toRad failing with decimals"
            );
            assert(
                toRad(1.5).toString() ==
                frac,
                "toRad failing with decimals"
            );
        });    
    })


});


