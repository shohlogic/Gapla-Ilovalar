const { withInfoPlist } = require('expo/config-plugins');

module.exports = function withProviderNetworking(config) {
  return withInfoPlist(config, (mod) => {
    mod.modResults.NSLocalNetworkUsageDescription =
      "Lokal tarmog'ingizda o'zingiz sozlagan AI xizmatlariga ulanish uchun kerak.";
    mod.modResults.NSAppTransportSecurity = {
      ...mod.modResults.NSAppTransportSecurity,
      NSAllowsLocalNetworking: true,
    };
    return mod;
  });
};
