export function cld(url: string, width?: number): string {
  const marker = "/image/upload/";
  if (!url.includes("res.cloudinary.com") || !url.includes(marker)) return url;
  const t = ["f_webp", "q_auto", width ? `w_${width}` : null, width ? "c_limit" : null].filter(Boolean).join(",");
  const [base, rest] = url.split(marker);
  if (/^[a-z]_[^/]*\//.test(rest) && !/^v\d+\//.test(rest)) return url;
  return `${base}${marker}${t}/${rest}`;
}
