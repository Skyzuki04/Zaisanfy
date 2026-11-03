import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@zaisanfy/schemas"],
  images: {
    remotePatterns: [{ protocol: "https", hostname: "res.cloudinary.com" }],
  },
};

export default nextConfig;
