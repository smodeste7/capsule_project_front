/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  images: {
    domains: ["cdn.vox-cdn.com", "techcrunch.com", "s.yimg.com"],
    loader: "akamai", // Spécifier que vous utilisez un loader personnalisé
    path: "", // Cette propriété n'est plus nécessaire ici, car le chemin est géré par votre loader
  },
  output: "export",
};

module.exports = nextConfig;
