const supportPageUrl = 'https://chickentriip2.com/support.html';
const privacyPolicyPageUrl = 'https://chickentriip2.com/privacy-policy.html';

const leaderboardApiUrl = 'https://api.chickentrip2.com/v1/leaderboard';
const skinStoreApiUrl = 'https://api.chickentrip2.com/v1/skins/catalog';
const achievementsApiUrl = 'https://api.chickentrip2.com/v1/achievements';
const dailyChallengeUrl = 'https://api.chickentrip2.com/v1/daily-challenge';
const playerProfileUrl = 'https://api.chickentrip2.com/v1/player/profile';
const tournamentApiUrl = 'https://api.chickentrip2.com/v1/tournaments';

String buildLeaderboardUrl(String season) =>
    '$leaderboardApiUrl?season=$season';

String buildProfileUrl(String playerId) =>
    '$playerProfileUrl/$playerId';
