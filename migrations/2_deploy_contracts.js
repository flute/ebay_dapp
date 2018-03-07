// var ConvertLib = artifacts.require("./ConvertLib.sol");
// var MetaCoin = artifacts.require("./MetaCoin.sol");

// module.exports = function(deployer) {
//   deployer.deploy(ConvertLib);
//   deployer.link(ConvertLib, MetaCoin);
//   deployer.deploy(MetaCoin);
// };

// var EcommerceStore = artifacts.require("../contracts/EcommerceStore.sol");
// // var MetaCoin = artifacts.require("./MetaCoin.sol");

// module.exports = function(deployer) {
//   deployer.deploy(EcommerceStore);
// //   deployer.link(ConvertLib, MetaCoin);
// //   deployer.deploy(MetaCoin);
// };


var EcommerceStore = artifacts.require("./EcommerceStore.sol");

module.exports = function(deployer) {
    deployer.deploy(EcommerceStore);
};