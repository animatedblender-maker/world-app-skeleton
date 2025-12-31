import express from "express";
import cors from "cors";
import fs from "fs";
import path from "path";
import { createYoga, createSchema } from "graphql-yoga";

type Country = { code: string; name: string };

const app = express();
app.use(cors());

// Load countries from local JSON
const countriesPath = path.join(process.cwd(), "src", "data", "countries.min.json");
const COUNTRIES: Country[] = JSON.parse(fs.readFileSync(countriesPath, "utf-8"));

function normalize(s: string) {
  return s.trim().toLowerCase();
}

const schema = createSchema({
  typeDefs: /* GraphQL */ `
    type Country {
      code: String!
      name: String!
    }

    type Query {
      health: String!
      countries: [Country!]!
      searchCountries(q: String!): [Country!]!
    }
  `,
  resolvers: {
    Query: {
      health: () => "ok",
      countries: () => COUNTRIES,
      searchCountries: (_: unknown, args: { q: string }) => {
        const q = normalize(args.q);
        if (!q) return [];
        // simple contains match (we can add fuzzy later)
        return COUNTRIES.filter(
          (c) => normalize(c.name).includes(q) || normalize(c.code).includes(q)
        ).slice(0, 10);
      }
    }
  }
});

const yoga = createYoga({
  graphqlEndpoint: "/graphql",
  schema
});

app.use("/graphql", yoga);

const port = Number(process.env.PORT || 3000);
app.listen(port, () => {
  console.log(`✅ GraphQL running at http://localhost:${port}/graphql`);
});
