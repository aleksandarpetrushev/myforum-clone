export interface User {
  id: number;
  email: string;
  name: string;
  location: string | null;
}

export interface Session {
  token: string;
  user: User;
}

export interface Topic {
  id: number;
  name: string;
  slug: string;
  followed?: boolean;
}

export interface EventSummary {
  id: number;
  title: string;
  starts_at: string;
  ends_at: string;
  location: string;
  kind: string;
  capacity: number;
  reserved_spots: number;
  status: string;
  cancelled_at?: string | null;
  organization: { id: number; name: string };
  topics: Topic[];
  description?: string;
  speakers?: { id: number; name: string; title: string | null }[];
  visibility?: EventVisibility;
  allowed_organization_ids?: number[];
  // Event detail only, per viewer: their own registration, if any (MF-202).
  my_registration?: Pick<Registration, 'id' | 'status' | 'cancelled_by' | 'waitlist_position' | 'offer_expires_at'> | null;
  // Event detail only, for the organizer's admins.
  waitlist_count?: number;
}

export type EventVisibility = 'public' | 'organization_restricted';

export interface Organization {
  id: number;
  name: string;
}

export interface CreateEventRequest {
  organization_id: number;
  title: string;
  description: string;
  location: string;
  kind: 'online' | 'in_person';
  capacity: number;
  starts_at: string;
  ends_at: string;
  status: 'draft' | 'published';
  visibility: EventVisibility;
  allowed_organization_ids: number[];
  topic_ids: number[];
}

export interface ValidationError {
  code: string;
  message: string;
  details?: Record<string, string[]>;
}

export interface Registration {
  id: number;
  // confirmed, cancelled, failed, or the waitlist states waitlisted and offered (MF-202).
  status: string;
  cancelled_by?: 'participant' | 'organizer' | 'offer_expired' | null;
  event_id: number;
  // Only while waitlisted: 1 is first in line.
  waitlist_position?: number;
  // Only while offered: the seat is held until then.
  offer_expires_at?: string;
  event?: { id: number; title: string; starts_at: string; ends_at?: string; location: string; status?: string } | null;
}

// Upcoming soonest first, Past most recent first; the server decides the split and the order.
export interface MyRegistrations {
  upcoming: Registration[];
  past: Registration[];
}

export interface NotificationItem {
  id: number;
  kind: string;
  title: string;
  body: string;
  read_at: string | null;
  created_at: string;
}

export interface NotificationPage {
  data: NotificationItem[];
  unread_count: number;
  next_cursor: string | null;
}

export interface NotificationPreferences {
  registration_confirmed_enabled: boolean;
  registration_cancelled_enabled: boolean;
  event_cancelled_enabled: boolean;
}

export interface ApiError {
  error: { code: string; message: string };
}
