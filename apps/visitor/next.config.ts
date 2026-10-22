import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Los esquemas Zod compartidos se usan en TypeScript directo desde packages/schemas
  transpilePackages: ["@zaisanfy/schemas"],
  images: {
    // Las fotos y las imágenes 360 se sirven desde Cloudinary
    remotePatterns: [{ protocol: "https", hostname: "res.cloudinary.com" }],
  },
};

export default nextConfig;
