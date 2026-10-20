import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    // Las fotos y las imágenes 360 se sirven desde Cloudinary
    remotePatterns: [{ protocol: "https", hostname: "res.cloudinary.com" }],
  },
};

export default nextConfig;
