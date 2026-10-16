export async function isOwnerCaller(userId, lookupRole) {
  if (typeof userId !== 'string' || !userId) return false;
  try {
    return await lookupRole(userId) === 'owner';
  } catch {
    return false;
  }
}
