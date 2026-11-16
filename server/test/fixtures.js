// Hand-written responses in the shape of Sportmonks' v3 documentation, for the mapping tests.
// When the real key arrives, `npm run probe` saves real responses to test/real/ to compare.
export const standings = {
  data: [
    {
      participant_id: 9, position: 2, points: 18,
      participant: { id: 9, name: "Arsenal", short_code: "ARS" },
      rule: { type: { name: "UEFA Champions League", developer_name: "UEFA_CHAMPIONS_LEAGUE" } },
      details: [
        { type_id: 129, value: 7 }, { type_id: 130, value: 6 }, { type_id: 131, value: 0 },
        { type_id: 132, value: 1 }, { type_id: 133, value: 14 }, { type_id: 134, value: 8 },
      ],
    },
    {
      participant_id: 18, position: 1, points: 21,
      participant: { id: 18, name: "Manchester City", short_code: "MCI" },
      details: [
        { type_id: 129, value: 7, type: { developer_name: "OVERALL_MATCHES" } }, { type_id: 130, value: 7 },
        { type_id: 131, value: 0 }, { type_id: 132, value: 0 }, { type_id: 179, value: 12 },
      ],
    },
    {
      participant_id: 77, position: 19, points: 5,
      participant: { id: 77, name: "Nottingham Forest", short_code: "NFO" },
      rule: { type: { name: "Relegation" } },
      details: [{ type_id: 129, value: 7 }, { type_id: 133, value: 4 }, { type_id: 134, value: 15 }],
    },
  ],
};

export const topscorers = {
  data: [
    { player_id: 1, participant_id: 9, type_id: 208, total: 6, player: { id: 1, display_name: "Bukayo Saka",
      statistics: [{ details: [{ type_id: 321, value: { total: 7 } }] }] }, participant: { id: 9, name: "Arsenal" } },
    { player_id: 1, participant_id: 9, type_id: 209, total: 4, player: { id: 1, display_name: "Bukayo Saka" }, participant: { id: 9, name: "Arsenal" } },
    { player_id: 2, participant_id: 18, type_id: 208, total: 9, player: { id: 2, common_name: "E. Haaland" }, participant: { id: 18, name: "Manchester City" } },
  ],
};

export const sidelined = {
  data: [
    {
      id: 9, name: "Arsenal", short_code: "ARS",
      sidelined: [
        { player_id: 1, category: "injury", start_date: "2026-10-18", end_date: "2026-11-12", completed: false,
          player: { display_name: "Bukayo Saka" }, type: { name: "Hamstring Injury" } },
        { player_id: 3, category: "injury", start_date: "2026-09-01", end_date: "2026-09-20", completed: true,
          player: { display_name: "Old Injury" }, type: { name: "Knee Injury" } },
        { player_id: 4, category: "injury", start_date: "2026-10-20", end_date: "2026-10-23", completed: false,
          player: { display_name: "Nearly Back" }, type: { name: "Knock" } },
        { player_id: 5, category: "suspension", start_date: "2026-10-19", end_date: null, completed: false,
          player: { display_name: "Red Card" } },
      ],
    },
  ],
};

export const fixtures = {
  data: [
    {
      id: 1001, starting_at: "2026-10-18 14:00:00", starting_at_timestamp: 1792504800,
      state: { developer_name: "FT" },
      participants: [
        { id: 9, name: "Arsenal", meta: { location: "home" } },
        { id: 77, name: "Nottingham Forest", meta: { location: "away" } },
      ],
      scores: [
        { description: "1ST_HALF", score: { goals: 0, participant: "home" } },
        { description: "CURRENT", score: { goals: 2, participant: "home" } },
        { description: "CURRENT", score: { goals: 1, participant: "away" } },
      ],
      events: [
        { type_id: 14, participant_id: 9, player_name: "Bukayo Saka", minute: 54 },
        { type_id: 15, participant_id: 77, player_name: "Murillo", minute: 70 },
        { type_id: 16, participant_id: 77, player_name: "Chris Wood", minute: 88, extra_minute: 2 },
        { type_id: 19, participant_id: 77, player_name: "Booked Player", minute: 30 },
      ],
    },
    {
      id: 1002, starting_at: "2026-10-25 16:30:00",
      state: { developer_name: "NS" },
      participants: [
        { id: 18, name: "Manchester City", meta: { location: "home" } },
        { id: 9, name: "Arsenal", meta: { location: "away" } },
      ],
      scores: [], events: [],
    },
  ],
};

// A finished match with line-ups and per-player stats (Sportmonks v3 shape).
export const lineups = {
  data: [
    {
      id: 2001, starting_at: "2026-10-18 14:00:00", state: { developer_name: "FT" },
      participants: [
        { id: 9, name: "Arsenal", meta: { location: "home" } },
        { id: 77, name: "Nottingham Forest", meta: { location: "away" } },
      ],
      scores: [
        { description: "CURRENT", score: { goals: 2, participant: "home" } },
        { description: "CURRENT", score: { goals: 0, participant: "away" } },
      ],
      lineups: [
        { player_id: 1, team_id: 9, player_name: "Bukayo Saka", position_id: 27, type_id: 11, details: [
          { type_id: 119, data: { value: 90 } }, { type_id: 52, data: { value: 1 } }, { type_id: 86, data: { value: 3 } }, { type_id: 117, data: { value: 2 } } ] },
        { player_id: 6, team_id: 9, player_name: "William Saliba", position_id: 25, type_id: 11, details: [
          { type_id: 119, data: { value: 90 } }, { type_id: 78, data: { value: 3 } }, { type_id: 100, data: { value: 2 } },
          { type_id: 105, data: { value: 8 } }, { type_id: 106, data: { value: 6 } } ] },
        { player_id: 30, team_id: 77, player_name: "Matz Sels", position_id: 24, type_id: 11, details: [
          { type_id: 119, data: { value: 90 } }, { type_id: 57, data: { value: 5 } } ] },
        { player_id: 31, team_id: 77, player_name: "Unused Sub", position_id: 26, type_id: 12, details: [] },
      ],
    },
    { id: 2002, starting_at: "2026-10-25 14:00:00", state: { developer_name: "NS" }, participants: [], lineups: [] },
  ],
};
