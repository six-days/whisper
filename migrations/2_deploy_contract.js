const Whisper = artifacts.require("Whisper");

module.exports = function(deployer) {
  deployer.deploy(Whisper, '0x627306090abab3a6e1400e9345bc60c78a8bef57');
};
