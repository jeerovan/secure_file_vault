import type { LayoutServerLoad } from './$types';
export const load: LayoutServerLoad = async ({ cookies, locals: { safeGetSession } }) => {
	const { session, user } = await safeGetSession();
	return {
		cookies: cookies.getAll(),
		session,
		user
	};
};
